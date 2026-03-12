import 'dart:convert';
import 'dart:io';

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
  });

  final List<String> lines;
  final List<String> loadedSources;
  final bool usedCachedData;
}

class FilterListRepository {
  FilterListRepository({
    Dio? dio,
    AssetBundle? assetBundle,
  }) : _dio = dio ?? Dio(),
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
    final mergedLines = <String>[];
    final loadedSources = <String>[];
    var usedCachedData = false;

    for (final listId in config.selectedListIds) {
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

      final remoteLines = await _loadRemoteWithFallback(
        listId: listId,
        remoteUrl: remoteUrl,
        config: config,
        logger: logger,
      );
      if (remoteLines.lines.isNotEmpty) {
        mergedLines.addAll(remoteLines.lines);
        loadedSources.add(remoteLines.sourceLabel);
        usedCachedData = usedCachedData || remoteLines.usedCachedData;
      }
    }

    return FilterListBundle(
      lines: List<String>.unmodifiable(mergedLines),
      loadedSources: List<String>.unmodifiable(loadedSources),
      usedCachedData: usedCachedData,
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

  Future<_RemoteListResult> _loadRemoteWithFallback({
    required String listId,
    required String remoteUrl,
    required AdblockConfig config,
    required AdblockDebugLogger logger,
  }) async {
    final cacheDir = await _resolveCacheDirectory();
    final manifest = await _readManifest(cacheDir);
    final remoteCacheFile = File(
      '${cacheDir.path}${Platform.pathSeparator}$_cachedRemotePrefix$listId$_cachedRemoteSuffix',
    );

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastFetchMs = (manifest[listId]?['lastFetchMs'] as int?) ?? 0;
    final refreshIntervalMs = config.remoteListRefreshInterval.inMilliseconds;
    final shouldRefresh =
        config.remoteListRefreshEnabled &&
        (nowMs - lastFetchMs >= refreshIntervalMs || !remoteCacheFile.existsSync());

    if (shouldRefresh) {
      try {
        final response = await _dio.get<String>(
          remoteUrl,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 10),
          ),
        );
        final body = response.data?.trim() ?? '';
        if (body.isNotEmpty) {
          await remoteCacheFile.writeAsString(body, flush: true);
          manifest[listId] = <String, dynamic>{
            'url': remoteUrl,
            'lastFetchMs': nowMs,
            'contentLength': body.length,
          };
          await _writeManifest(cacheDir, manifest);
          logger.log('remote list refreshed id=$listId');
          return _RemoteListResult(
            lines: body.split(RegExp(r'\r?\n')),
            sourceLabel: 'remote:$remoteUrl',
            usedCachedData: false,
          );
        }
      } catch (_) {
        logger.log('remote list refresh failed id=$listId');
      }
    }

    if (remoteCacheFile.existsSync()) {
      try {
        final cached = await remoteCacheFile.readAsString();
        if (cached.trim().isNotEmpty) {
          return _RemoteListResult(
            lines: cached.split(RegExp(r'\r?\n')),
            sourceLabel: 'cache:remote:$listId',
            usedCachedData: true,
          );
        }
      } catch (_) {
        logger.log('remote cache read failed id=$listId');
      }
    }

    return const _RemoteListResult(
      lines: <String>[],
      sourceLabel: 'remote:empty',
      usedCachedData: false,
    );
  }

  String? _assetPathForListId(String listId) {
    switch (listId) {
      case 'basic':
        return AppConfig.filterAssetPath;
      default:
        return null;
    }
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

class _RemoteListResult {
  const _RemoteListResult({
    required this.lines,
    required this.sourceLabel,
    required this.usedCachedData,
  });

  final List<String> lines;
  final String sourceLabel;
  final bool usedCachedData;
}
