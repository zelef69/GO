import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/config/app_config.dart';
import 'adblock_config.dart';
import 'adblock_debug_logger.dart';

class FilterListBundle {
  const FilterListBundle({
    required this.lines,
    required this.loadedSources,
    required this.usedCachedData,
    required this.rawFilterText,
    required this.resourcesJson,
    required this.enabledTags,
    required this.catalogSourcesJson,
    required this.firstPartyHeuristicsProfileEnabled,
  });

  final List<String> lines;
  final List<String> loadedSources;
  final bool usedCachedData;
  final String rawFilterText;
  final String resourcesJson;
  final List<String> enabledTags;
  final String catalogSourcesJson;
  final bool firstPartyHeuristicsProfileEnabled;
}

class FilterListRepository {
  FilterListRepository({Dio? dio, AssetBundle? assetBundle})
    : _dio = dio ?? Dio(),
      _rootBundle = assetBundle ?? rootBundle;

  static const String _cacheDirName = 'adblock';
  static const String _manifestFileName = 'filter_manifest.json';
  static const String _cachedRemotePrefix = 'remote_';
  static const String _cachedRemoteSuffix = '.txt';

  final Dio _dio;
  final AssetBundle _rootBundle;

  Future<FilterListBundle> loadLists({
    required AdblockConfig config,
    required AdblockDebugLogger logger,
  }) async {
    final braveBundle = await _loadBraveCatalogBundle(
      config: config,
      logger: logger,
    );
    if (braveBundle != null && braveBundle.lines.isNotEmpty) {
      return braveBundle;
    }

    return _loadLegacyBundle(config: config, logger: logger);
  }

  Future<FilterListBundle?> _loadBraveCatalogBundle({
    required AdblockConfig config,
    required AdblockDebugLogger logger,
  }) async {
    if (!config.braveCatalogEnabled || config.braveCatalogUrl.trim().isEmpty) {
      return null;
    }

    final catalogResult = await _loadRemoteTextWithFallback(
      cacheKey: 'brave_catalog',
      remoteUrl: config.braveCatalogUrl.trim(),
      config: config,
      logger: logger,
    );
    if (catalogResult.text.trim().isEmpty) {
      logger.log('brave catalog unavailable -> fallback legacy');
      return null;
    }

    final entries = _parseBraveCatalogEntries(
      catalogResult.text,
      logger: logger,
    );
    if (entries.isEmpty) {
      logger.log('brave catalog parsed empty -> fallback legacy');
      return null;
    }

    final activeEntries = _selectActiveBraveEntries(entries, config: config);
    if (activeEntries.isEmpty) {
      logger.log('brave catalog no active entries -> fallback legacy');
      return null;
    }

    final mergedLines = <String>[];
    final seenLines = <String>{};
    final loadedSources = <String>[];
    final enabledTags = <String>{};
    final nativeCatalogSources = <_NativeCatalogSourcePayload>[];
    var usedCachedData = catalogResult.usedCachedData;
    var firstPartyProfileEnabled = false;

    for (final entry in activeEntries) {
      if (_isFirstPartyCatalogEntry(entry)) {
        firstPartyProfileEnabled = true;
      }
      enabledTags.addAll(_tagsForEntry(entry));

      for (
        var sourceIndex = 0;
        sourceIndex < entry.sources.length;
        sourceIndex += 1
      ) {
        final source = entry.sources[sourceIndex];
        if (source.url.trim().isEmpty) {
          continue;
        }
        final sourceResult = await _loadCatalogSource(
          cacheKey: 'brave_${entry.uuid}_$sourceIndex',
          sourceUrl: source.url.trim(),
          config: config,
          logger: logger,
        );
        if (sourceResult.lines.isEmpty) {
          continue;
        }
        usedCachedData = usedCachedData || sourceResult.usedCachedData;
        final sourceLabel = source.title.isEmpty
            ? sourceResult.resolvedUrl
            : '${source.title} (${sourceResult.resolvedUrl})';
        loadedSources.add('catalog:${entry.uuid}:$sourceLabel');

        for (final rawLine in sourceResult.lines) {
          final normalized = rawLine.trimRight();
          if (normalized.isEmpty) {
            continue;
          }
          if (seenLines.add(normalized)) {
            mergedLines.add(normalized);
          }
        }

        nativeCatalogSources.add(
          _NativeCatalogSourcePayload(
            text: sourceResult.rawText,
            format: source.format,
            permissionMask: source.permissionMask >= 0
                ? source.permissionMask
                : entry.permissionMask,
          ),
        );
      }
    }

    if (mergedLines.isEmpty) {
      logger.log('brave catalog sources empty -> fallback legacy');
      return null;
    }

    final resourcesJson = await _loadBraveResourcesJson(
      config: config,
      logger: logger,
    );
    logger.log(
      'brave catalog loaded entries=${activeEntries.length} lines=${mergedLines.length} resourcesChars=${resourcesJson.length} firstPartyProfile=$firstPartyProfileEnabled',
    );

    return FilterListBundle(
      lines: List<String>.unmodifiable(mergedLines),
      loadedSources: List<String>.unmodifiable(loadedSources),
      usedCachedData: usedCachedData,
      rawFilterText: mergedLines.join('\n'),
      resourcesJson: resourcesJson,
      enabledTags: List<String>.unmodifiable(enabledTags),
      catalogSourcesJson: jsonEncode(
        nativeCatalogSources
            .where((source) => source.text.trim().isNotEmpty)
            .map((source) => source.toJson())
            .toList(growable: false),
      ),
      firstPartyHeuristicsProfileEnabled: firstPartyProfileEnabled,
    );
  }

  Future<_CatalogSourceLoadResult> _loadCatalogSource({
    required String cacheKey,
    required String sourceUrl,
    required AdblockConfig config,
    required AdblockDebugLogger logger,
  }) async {
    var result = await _loadRemoteTextWithFallback(
      cacheKey: cacheKey,
      remoteUrl: sourceUrl,
      config: config,
      logger: logger,
    );
    if (result.text.trim().isEmpty) {
      return _CatalogSourceLoadResult.empty(sourceUrl);
    }

    var metadata = _parseFilterListHeaderMetadata(result.text);
    var resolvedUrl = sourceUrl;

    final redirectUrl = metadata.redirectUrl;
    if (redirectUrl != null &&
        redirectUrl.isNotEmpty &&
        redirectUrl != sourceUrl) {
      final redirected = await _loadRemoteTextWithFallback(
        cacheKey: '${cacheKey}_redirect',
        remoteUrl: redirectUrl,
        config: config,
        logger: logger,
      );
      if (redirected.text.trim().isNotEmpty) {
        result = redirected;
        metadata = _parseFilterListHeaderMetadata(result.text);
        resolvedUrl = redirectUrl;
      }
    }

    final refreshDuration =
        metadata.expires ?? config.remoteListRefreshInterval;
    await _updateNextRefreshAt(
      cacheKey: cacheKey,
      nextRefreshAtMs: DateTime.now()
          .add(refreshDuration)
          .millisecondsSinceEpoch,
    );

    return _CatalogSourceLoadResult(
      lines: result.text.split(RegExp(r'\r?\n')),
      rawText: result.text,
      usedCachedData: result.usedCachedData,
      resolvedUrl: resolvedUrl,
    );
  }

  Future<String> _loadBraveResourcesJson({
    required AdblockConfig config,
    required AdblockDebugLogger logger,
  }) async {
    if (!config.braveResourcesEnabled ||
        config.braveResourcesUrl.trim().isEmpty) {
      return '[]';
    }
    final result = await _loadRemoteTextWithFallback(
      cacheKey: 'brave_resources',
      remoteUrl: config.braveResourcesUrl.trim(),
      config: config,
      logger: logger,
    );
    final text = result.text.trim();
    if (text.isEmpty) {
      return '[]';
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is List<dynamic>) {
        return text;
      }
    } catch (_) {}
    logger.log('brave resources invalid json -> using empty');
    return '[]';
  }

  Future<FilterListBundle> _loadLegacyBundle({
    required AdblockConfig config,
    required AdblockDebugLogger logger,
  }) async {
    final mergedLines = <String>[];
    final loadedSources = <String>[];
    var usedCachedData = false;

    final listIds = config.selectedListIds.isEmpty
        ? const <String>['basic']
        : config.selectedListIds;

    for (final listId in listIds) {
      final assetPath = _assetPathForListId(listId);
      if (assetPath != null) {
        final bundled = await _loadBundledList(assetPath, logger: logger);
        if (bundled.isNotEmpty) {
          mergedLines.addAll(bundled);
          loadedSources.add('asset:$assetPath');
        }
      }

      final remoteUrl = AppConfig.remoteFilterListUrls[listId];
      if (remoteUrl == null || remoteUrl.isEmpty) {
        continue;
      }

      final remoteText = await _loadRemoteTextWithFallback(
        cacheKey: 'legacy_$listId',
        remoteUrl: remoteUrl,
        config: config,
        logger: logger,
      );
      if (remoteText.text.trim().isNotEmpty) {
        mergedLines.addAll(remoteText.text.split(RegExp(r'\r?\n')));
        loadedSources.add(remoteText.sourceLabel);
        usedCachedData = usedCachedData || remoteText.usedCachedData;
      }
    }

    final normalized = mergedLines
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    return FilterListBundle(
      lines: normalized,
      loadedSources: List<String>.unmodifiable(loadedSources),
      usedCachedData: usedCachedData,
      rawFilterText: normalized.join('\n'),
      resourcesJson: '[]',
      enabledTags: const <String>[],
      catalogSourcesJson: '[]',
      firstPartyHeuristicsProfileEnabled: false,
    );
  }

  Future<List<String>> _loadBundledList(
    String assetPath, {
    required AdblockDebugLogger logger,
  }) async {
    try {
      final raw = await _rootBundle.loadString(assetPath);
      return raw.split(RegExp(r'\r?\n'));
    } catch (_) {
      logger.log('bundle list load failed path=$assetPath');
      return const <String>[];
    }
  }

  Future<_RemoteTextResult> _loadRemoteTextWithFallback({
    required String cacheKey,
    required String remoteUrl,
    required AdblockConfig config,
    required AdblockDebugLogger logger,
    bool forceRefresh = false,
  }) async {
    final cacheDir = await _resolveCacheDirectory();
    final manifest = await _readManifest(cacheDir);
    final manifestEntry = manifest[cacheKey];
    final entry = Map<String, dynamic>.from(
      manifestEntry is Map ? manifestEntry : <String, dynamic>{},
    );
    final file = File(
      '${cacheDir.path}${Platform.pathSeparator}$_cachedRemotePrefix${_cacheFileToken(cacheKey)}$_cachedRemoteSuffix',
    );

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastFetchMs = (entry['lastFetchMs'] as int?) ?? 0;
    final defaultNextRefreshAtMs =
        lastFetchMs + config.remoteListRefreshInterval.inMilliseconds;
    final nextRefreshAtMs =
        (entry['nextRefreshAtMs'] as int?) ?? defaultNextRefreshAtMs;
    final shouldRefresh =
        forceRefresh ||
        !file.existsSync() ||
        (config.remoteListRefreshEnabled && nowMs >= nextRefreshAtMs);

    if (shouldRefresh) {
      final headers = <String, String>{};
      final etag = entry['etag']?.toString().trim() ?? '';
      final lastModified = entry['lastModified']?.toString().trim() ?? '';
      if (etag.isNotEmpty) {
        headers['If-None-Match'] = etag;
      }
      if (lastModified.isNotEmpty) {
        headers['If-Modified-Since'] = lastModified;
      }

      try {
        final response = await _dio.get<String>(
          remoteUrl,
          options: Options(
            responseType: ResponseType.plain,
            headers: headers,
            followRedirects: true,
            maxRedirects: 6,
            receiveTimeout: const Duration(seconds: 25),
            sendTimeout: const Duration(seconds: 12),
            validateStatus: (status) =>
                status != null &&
                (status == 304 || (status >= 200 && status < 300)),
          ),
        );

        final statusCode = response.statusCode ?? 0;
        if (statusCode == 304 && file.existsSync()) {
          entry['lastFetchMs'] = nowMs;
          entry['nextRefreshAtMs'] =
              nowMs + config.remoteListRefreshInterval.inMilliseconds;
          manifest[cacheKey] = entry;
          await _writeManifest(cacheDir, manifest);
        } else {
          final body = response.data?.trim() ?? '';
          if (body.isNotEmpty) {
            await file.writeAsString(body, flush: true);
            entry['url'] = remoteUrl;
            entry['lastFetchMs'] = nowMs;
            entry['nextRefreshAtMs'] =
                nowMs + config.remoteListRefreshInterval.inMilliseconds;
            entry['contentLength'] = body.length;
            entry['etag'] = response.headers.value('etag') ?? '';
            entry['lastModified'] =
                response.headers.value('last-modified') ?? '';
            manifest[cacheKey] = entry;
            await _writeManifest(cacheDir, manifest);
            return _RemoteTextResult(
              text: body,
              sourceLabel: 'remote:$remoteUrl',
              usedCachedData: false,
            );
          }
        }
      } catch (_) {
        logger.log('remote load failed key=$cacheKey');
      }
    }

    if (file.existsSync()) {
      try {
        final cached = await file.readAsString();
        if (cached.trim().isNotEmpty) {
          return _RemoteTextResult(
            text: cached,
            sourceLabel: 'cache:$cacheKey',
            usedCachedData: true,
          );
        }
      } catch (_) {
        logger.log('remote cache read failed key=$cacheKey');
      }
    }

    return _RemoteTextResult.empty(remoteUrl);
  }

  Future<void> _updateNextRefreshAt({
    required String cacheKey,
    required int nextRefreshAtMs,
  }) async {
    final cacheDir = await _resolveCacheDirectory();
    final manifest = await _readManifest(cacheDir);
    final manifestEntry = manifest[cacheKey];
    final entry = Map<String, dynamic>.from(
      manifestEntry is Map ? manifestEntry : <String, dynamic>{},
    );
    entry['nextRefreshAtMs'] = nextRefreshAtMs;
    manifest[cacheKey] = entry;
    await _writeManifest(cacheDir, manifest);
  }

  List<_BraveCatalogEntry> _parseBraveCatalogEntries(
    String rawCatalog, {
    required AdblockDebugLogger logger,
  }) {
    try {
      final decoded = jsonDecode(rawCatalog);
      if (decoded is! List<dynamic>) {
        return const <_BraveCatalogEntry>[];
      }
      final parsed = <_BraveCatalogEntry>[];
      for (final entry in decoded) {
        if (entry is! Map) {
          continue;
        }
        final mapped = entry.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final parsedEntry = _BraveCatalogEntry.fromJson(mapped);
        parsed.add(parsedEntry);
      }
      return parsed;
    } catch (_) {
      logger.log('brave catalog parse failed');
      return const <_BraveCatalogEntry>[];
    }
  }

  List<_BraveCatalogEntry> _selectActiveBraveEntries(
    List<_BraveCatalogEntry> entries, {
    required AdblockConfig config,
  }) {
    final selectedIds = config.selectedListIds
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();

    bool entryMatches(_BraveCatalogEntry entry) {
      if (!_entryMatchesPlatform(entry)) {
        return false;
      }
      if (!_entryMatchesRegion(entry, config.region)) {
        return false;
      }
      if (selectedIds.isEmpty) {
        return entry.defaultEnabled;
      }
      return selectedIds.contains(entry.uuid.toLowerCase());
    }

    final selected = entries.where(entryMatches).toList(growable: false);
    if (selected.isNotEmpty) {
      return selected;
    }

    return entries
        .where(
          (entry) =>
              entry.defaultEnabled &&
              _entryMatchesPlatform(entry) &&
              _entryMatchesRegion(entry, config.region),
        )
        .toList(growable: false);
  }

  bool _entryMatchesPlatform(_BraveCatalogEntry entry) {
    if (entry.platforms.isEmpty) {
      return true;
    }
    final platforms = entry.platforms
        .map((value) => value.toLowerCase())
        .toSet();
    return platforms.contains('android') ||
        platforms.contains('all') ||
        platforms.contains('mobile');
  }

  bool _entryMatchesRegion(_BraveCatalogEntry entry, String region) {
    if (entry.langs.isEmpty) {
      return true;
    }
    final normalizedRegion = region.trim().toLowerCase();
    if (normalizedRegion.isEmpty || normalizedRegion == 'global') {
      return true;
    }
    final regionToken = normalizedRegion.split(RegExp(r'[-_]')).first;
    for (final lang in entry.langs) {
      final normalizedLang = lang.trim().toLowerCase();
      if (normalizedLang == regionToken ||
          normalizedLang.startsWith('$regionToken-') ||
          normalizedLang.startsWith('${regionToken}_')) {
        return true;
      }
    }
    return false;
  }

  bool _isFirstPartyCatalogEntry(_BraveCatalogEntry entry) {
    if (entry.firstPartyProtections) {
      return true;
    }
    final title = entry.title.toLowerCase();
    return title.contains('first party') || title.contains('first-party');
  }

  Iterable<String> _tagsForEntry(_BraveCatalogEntry entry) sync* {
    if (_isFirstPartyCatalogEntry(entry)) {
      yield 'brave_first_party';
    }
    if (entry.permissionMask > 0) {
      yield 'permission_${entry.permissionMask}';
    }
    for (final lang in entry.langs) {
      final normalized = lang.trim().toLowerCase();
      if (normalized.isNotEmpty) {
        yield 'lang_$normalized';
      }
    }
    for (final platform in entry.platforms) {
      final normalized = platform.trim().toLowerCase();
      if (normalized.isNotEmpty) {
        yield 'platform_$normalized';
      }
    }
  }

  _FilterListHeaderMetadata _parseFilterListHeaderMetadata(String listText) {
    String? title;
    String? redirectUrl;
    Duration? expires;
    var lineCount = 0;
    for (final rawLine in listText.split(RegExp(r'\r?\n'))) {
      lineCount += 1;
      if (lineCount > 180) {
        break;
      }
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      if (!line.startsWith('!') && !line.startsWith('[')) {
        break;
      }
      if (!line.startsWith('!')) {
        continue;
      }
      final comment = line.substring(1).trim();
      final separator = comment.indexOf(':');
      if (separator == -1) {
        continue;
      }
      final key = comment.substring(0, separator).trim().toLowerCase();
      final value = comment.substring(separator + 1).trim();
      if (value.isEmpty) {
        continue;
      }
      switch (key) {
        case 'title':
          title ??= value;
        case 'redirect':
          redirectUrl ??= value;
        case 'expires':
          expires ??= _parseExpiresDuration(value);
      }
    }
    return _FilterListHeaderMetadata(
      title: title,
      redirectUrl: redirectUrl,
      expires: expires,
    );
  }

  Duration? _parseExpiresDuration(String rawValue) {
    final match = RegExp(
      r'^(\d+)\s*(hour|hours|day|days)$',
      caseSensitive: false,
    ).firstMatch(rawValue.trim());
    if (match == null) {
      return null;
    }
    final amount = int.tryParse(match.group(1) ?? '');
    if (amount == null || amount <= 0) {
      return null;
    }
    final unit = (match.group(2) ?? '').toLowerCase();
    if (unit.startsWith('hour')) {
      return Duration(hours: amount);
    }
    return Duration(days: amount);
  }

  String? _assetPathForListId(String listId) {
    switch (listId) {
      case 'basic':
        return AppConfig.filterAssetPath;
      default:
        return null;
    }
  }

  String _cacheFileToken(String cacheKey) {
    return sha1.convert(utf8.encode(cacheKey)).toString();
  }

  Future<Directory> _resolveCacheDirectory() async {
    final baseDirectory = await getApplicationSupportDirectory();
    final cacheDir = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}$_cacheDirName',
    );
    if (!cacheDir.existsSync()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<Map<String, dynamic>> _readManifest(Directory cacheDir) async {
    final file = File(
      '${cacheDir.path}${Platform.pathSeparator}$_manifestFileName',
    );
    if (!file.existsSync()) {
      return <String, dynamic>{};
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _writeManifest(
    Directory cacheDir,
    Map<String, dynamic> manifest,
  ) async {
    final file = File(
      '${cacheDir.path}${Platform.pathSeparator}$_manifestFileName',
    );
    await file.writeAsString(jsonEncode(manifest), flush: true);
  }
}

class _RemoteTextResult {
  const _RemoteTextResult({
    required this.text,
    required this.sourceLabel,
    required this.usedCachedData,
  });

  factory _RemoteTextResult.empty(String remoteUrl) {
    return _RemoteTextResult(
      text: '',
      sourceLabel: 'remote:empty:$remoteUrl',
      usedCachedData: false,
    );
  }

  final String text;
  final String sourceLabel;
  final bool usedCachedData;
}

class _CatalogSourceLoadResult {
  const _CatalogSourceLoadResult({
    required this.lines,
    required this.rawText,
    required this.usedCachedData,
    required this.resolvedUrl,
  });

  factory _CatalogSourceLoadResult.empty(String sourceUrl) {
    return _CatalogSourceLoadResult(
      lines: const <String>[],
      rawText: '',
      usedCachedData: false,
      resolvedUrl: sourceUrl,
    );
  }

  final List<String> lines;
  final String rawText;
  final bool usedCachedData;
  final String resolvedUrl;
}

class _FilterListHeaderMetadata {
  const _FilterListHeaderMetadata({
    required this.title,
    required this.redirectUrl,
    required this.expires,
  });

  final String? title;
  final String? redirectUrl;
  final Duration? expires;
}

class _BraveCatalogEntry {
  const _BraveCatalogEntry({
    required this.uuid,
    required this.title,
    required this.defaultEnabled,
    required this.firstPartyProtections,
    required this.langs,
    required this.platforms,
    required this.permissionMask,
    required this.sources,
  });

  factory _BraveCatalogEntry.fromJson(Map<String, dynamic> json) {
    List<String> asStringList(String key) {
      final value = json[key];
      if (value is List<dynamic>) {
        return value
            .map((entry) => entry.toString().trim())
            .where((entry) => entry.isNotEmpty)
            .toList(growable: false);
      }
      return const <String>[];
    }

    final sourcesRaw = json['sources'];
    final sources = <_BraveCatalogSource>[];
    if (sourcesRaw is List<dynamic>) {
      for (final source in sourcesRaw) {
        if (source is! Map) {
          continue;
        }
        final parsedSource = _BraveCatalogSource.fromJson(
          source.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (parsedSource != null) {
          sources.add(parsedSource);
        }
      }
    }

    return _BraveCatalogEntry(
      uuid: json['uuid']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
      defaultEnabled: json['default_enabled'] == true,
      firstPartyProtections: json['first_party_protections'] == true,
      langs: asStringList('langs'),
      platforms: asStringList('platforms'),
      permissionMask: (json['permission_mask'] as num?)?.toInt() ?? 0,
      sources: List<_BraveCatalogSource>.unmodifiable(sources),
    );
  }

  final String uuid;
  final String title;
  final bool defaultEnabled;
  final bool firstPartyProtections;
  final List<String> langs;
  final List<String> platforms;
  final int permissionMask;
  final List<_BraveCatalogSource> sources;
}

class _BraveCatalogSource {
  const _BraveCatalogSource({
    required this.url,
    required this.title,
    required this.format,
    required this.permissionMask,
  });

  static _BraveCatalogSource? fromJson(Map<String, dynamic> json) {
    final url = json['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      return null;
    }
    return _BraveCatalogSource(
      url: url,
      title: json['title']?.toString().trim() ?? '',
      format: json['format']?.toString().trim().isNotEmpty == true
          ? json['format'].toString().trim()
          : 'Standard',
      permissionMask: (json['permission_mask'] as num?)?.toInt() ?? -1,
    );
  }

  final String url;
  final String title;
  final String format;
  final int permissionMask;
}

class _NativeCatalogSourcePayload {
  const _NativeCatalogSourcePayload({
    required this.text,
    required this.format,
    required this.permissionMask,
  });

  final String text;
  final String format;
  final int permissionMask;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'text': text,
      'format': format,
      'permission_mask': permissionMask < 0 ? 0 : permissionMask,
    };
  }
}
