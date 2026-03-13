import 'dart:convert';

import '../core/adblock_config.dart';
import '../core/adblock_debug_logger.dart';
import '../core/filter_list_repository.dart';
import '../core/types.dart';

class FilterSourceManager {
  FilterSourceManager({FilterListRepository? repository})
    : _repository = repository ?? FilterListRepository();

  final FilterListRepository _repository;
  final Map<String, _CustomFilterSource> _customSources =
      <String, _CustomFilterSource>{};

  Future<FilterSourceSnapshot> load({
    required AdblockConfig config,
    required AdblockDebugLogger logger,
  }) async {
    final base = await _repository.loadLists(config: config, logger: logger);
    final mergedLines = <String>[...base.lines];
    final loadedSources = <String>[...base.loadedSources];
    final metadata = <FilterListMetadata>[
      FilterListMetadata(
        id: 'builtin',
        title: 'Built-in filter bundle',
        version: 'runtime',
        enabled: true,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        source: 'bundle+remote',
      ),
    ];

    for (final entry in _customSources.values) {
      metadata.add(entry.metadata);
      if (!entry.enabled) {
        continue;
      }
      final lines = entry.listText
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trimRight())
          .where((line) => line.isNotEmpty);
      mergedLines.addAll(lines);
      loadedSources.add('custom:${entry.metadata.id}');
    }

    final customFilterTextForNative = _buildCustomFilterTextForNative();
    final catalogSourcesJsonForNative = _appendCustomProviderCatalogSource(
      base.catalogSourcesJson,
      customFilterTextForNative,
    );

    return FilterSourceSnapshot(
      lines: List<String>.unmodifiable(mergedLines),
      rawFilterText: mergedLines.join('\n'),
      loadedSources: List<String>.unmodifiable(loadedSources),
      usedCachedData: base.usedCachedData,
      resourcesJson: base.resourcesJson,
      enabledTags: base.enabledTags,
      catalogSourcesJson: catalogSourcesJsonForNative,
      firstPartyHeuristicsProfileEnabled:
          base.firstPartyHeuristicsProfileEnabled,
      metadata: List<FilterListMetadata>.unmodifiable(metadata),
    );
  }

  String _buildCustomFilterTextForNative() {
    final customLines = <String>[];
    for (final entry in _customSources.values) {
      if (!entry.enabled) {
        continue;
      }
      final lines = entry.listText
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trimRight())
          .where((line) => line.isNotEmpty);
      customLines.addAll(lines);
    }
    return customLines.join('\n');
  }

  String _appendCustomProviderCatalogSource(
    String baseCatalogSourcesJson,
    String customFilterText,
  ) {
    if (customFilterText.trim().isEmpty) {
      return baseCatalogSourcesJson;
    }
    final trimmedBase = baseCatalogSourcesJson.trim();
    if (trimmedBase.isEmpty || trimmedBase == '[]') {
      return baseCatalogSourcesJson;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmedBase);
    } catch (_) {
      return baseCatalogSourcesJson;
    }
    if (decoded is! List<dynamic>) {
      return baseCatalogSourcesJson;
    }

    final mergedSources = List<dynamic>.from(decoded)
      ..add(<String, dynamic>{
        'text': customFilterText,
        'format': 'Standard',
        'permission_mask': 0,
      });
    return jsonEncode(mergedSources);
  }

  Future<FilterSourceSnapshot> refresh({
    required AdblockConfig config,
    required AdblockDebugLogger logger,
  }) {
    return load(config: config, logger: logger);
  }

  void addCustomList(String listText, {required FilterListMetadata metadata}) {
    _customSources[metadata.id] = _CustomFilterSource(
      listText: listText,
      metadata: metadata,
      enabled: metadata.enabled,
    );
  }

  void setCustomListEnabled(String id, bool enabled) {
    final existing = _customSources[id];
    if (existing == null) {
      return;
    }
    _customSources[id] = existing.copyWith(enabled: enabled);
  }

  void removeCustomList(String id) {
    _customSources.remove(id);
  }

  List<FilterListMetadata> metadata() {
    return _customSources.values
        .map((source) => source.metadata)
        .toList(growable: false);
  }
}

class _CustomFilterSource {
  const _CustomFilterSource({
    required this.listText,
    required this.metadata,
    required this.enabled,
  });

  final String listText;
  final FilterListMetadata metadata;
  final bool enabled;

  _CustomFilterSource copyWith({bool? enabled}) {
    return _CustomFilterSource(
      listText: listText,
      metadata: metadata,
      enabled: enabled ?? this.enabled,
    );
  }
}
