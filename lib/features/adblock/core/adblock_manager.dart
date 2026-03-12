import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain_lock/domain_policy_service.dart';
import '../adblock_engine_bridge.dart';
import '../models/adblock_rule.dart';
import 'adblock_config.dart';
import 'adblock_debug_logger.dart';
import 'adblock_metrics.dart';
import 'engine_adapter.dart';
import 'filter_compiler.dart';
import 'filter_list_repository.dart';
import 'request_blocker.dart';

class AdblockManager {
  factory AdblockManager({
    required DomainPolicyService domainPolicyService,
    required AdblockEngineBridge nativeEngineBridge,
    required AdblockEngineBridge fallbackEngineBridge,
    required AdblockConfig initialConfig,
  }) {
    final logger = AdblockDebugLogger(enabled: initialConfig.debugMode);
    final metrics = AdblockMetricsCollector();
    final engineAdapter = EngineAdapter(
      nativeEngineBridge: nativeEngineBridge,
      fallbackEngineBridge: fallbackEngineBridge,
      logger: logger,
    );
    final requestBlocker = RequestBlocker(
      domainPolicyService: domainPolicyService,
      logger: logger,
      metrics: metrics,
    )..setConfig(initialConfig);
    return AdblockManager._(
      filterListRepository: FilterListRepository(),
      filterCompiler: const FilterCompiler(),
      logger: logger,
      metrics: metrics,
      engineAdapter: engineAdapter,
      requestBlocker: requestBlocker,
      initialConfig: initialConfig,
    );
  }

  AdblockManager._({
    required FilterListRepository filterListRepository,
    required FilterCompiler filterCompiler,
    required AdblockDebugLogger logger,
    required AdblockMetricsCollector metrics,
    required EngineAdapter engineAdapter,
    required RequestBlocker requestBlocker,
    required AdblockConfig initialConfig,
  }) : _filterListRepository = filterListRepository,
       _filterCompiler = filterCompiler,
       _logger = logger,
       _metrics = metrics,
       _engineAdapter = engineAdapter,
       _requestBlocker = requestBlocker,
       _config = initialConfig;

  final FilterListRepository _filterListRepository;
  final FilterCompiler _filterCompiler;
  final AdblockDebugLogger _logger;
  final AdblockMetricsCollector _metrics;
  final EngineAdapter _engineAdapter;
  final RequestBlocker _requestBlocker;

  static const String _cacheDirName = 'adblock';
  static const String _compiledRulesFileName = 'compiled_rules_cache.json';

  AdblockConfig _config;
  Future<void>? _initializeFuture;
  bool _initialized = false;
  bool _disposed = false;
  String _activeRevision = '';
  int _activeRuleCount = 0;
  List<String> _loadedSources = const <String>[];
  bool _usedCachedList = false;

  bool get initialized => _initialized;
  bool get enabled => _config.enabled;
  bool get usingNativeEngine => _engineAdapter.usingNativeEngine;
  String get activeRevision => _activeRevision;
  int get activeRuleCount => _activeRuleCount;
  List<String> get loadedSources => _loadedSources;
  bool get usedCachedList => _usedCachedList;

  AdblockMetricsSnapshot get metricsSnapshot => _metrics.snapshot();

  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('AdblockManager already disposed');
    }
    if (_initialized) {
      return;
    }
    final pending = _initializeFuture;
    if (pending != null) {
      return pending;
    }

    final future = _initializeInternal();
    _initializeFuture = future;
    try {
      await future;
    } finally {
      _initializeFuture = null;
    }
  }

  Future<void> _initializeInternal() async {
    _requestBlocker.setConfig(_config);

    final listBundle = await _filterListRepository.loadLists(
      config: _config,
      logger: _logger,
    );
    _loadedSources = listBundle.loadedSources;
    _usedCachedList = listBundle.usedCachedData;

    final lines = listBundle.lines;
    if (lines.isEmpty) {
      _logger.log('filter list empty -> continue in allow mode');
      _requestBlocker.setEngine(_engineAdapter);
      _initialized = true;
      return;
    }

    final revision = _filterCompiler.computeRevision(lines);
    List<AdblockRule>? compiledFromCache = await _tryLoadCompiledRulesCache(
      expectedRevision: revision,
    );

    FilterCompilationResult compilationResult;
    if (compiledFromCache != null && compiledFromCache.isNotEmpty) {
      compilationResult = FilterCompilationResult(
        rules: compiledFromCache,
        revision: revision,
        parsedLines: lines.length,
        ignoredLines: 0,
      );
      _logger.log(
        'compiled rules cache hit revision=$revision rules=${compiledFromCache.length}',
      );
    } else {
      compilationResult = await _compileInBackground(lines);
      await _writeCompiledRulesCache(
        revision: compilationResult.revision,
        rules: compilationResult.rules,
      );
      _logger.log(
        'compiled rules built revision=${compilationResult.revision} parsed=${compilationResult.parsedLines} ignored=${compilationResult.ignoredLines}',
      );
    }

    try {
      await _engineAdapter.initialize(compilationResult.rules);
    } catch (_) {
      // Fail-safe: keep WebView loading normally when engine startup fails.
      _logger.log('engine initialization failed -> continue fail-open');
    }

    _requestBlocker.setEngine(_engineAdapter);
    _requestBlocker.setConfig(_config);
    _activeRevision = compilationResult.revision;
    _activeRuleCount = compilationResult.rules.length;
    _initialized = true;
    _logger.log(
      'manager initialized rules=$_activeRuleCount native=${_engineAdapter.usingNativeEngine}',
    );
  }

  Future<FilterCompilationResult> _compileInBackground(
    List<String> lines,
  ) async {
    try {
      final payload = await compute<Map<String, dynamic>, Map<String, dynamic>>(
        _compileRulesWorker,
        <String, dynamic>{'lines': lines},
      );
      final revision = payload['revision']?.toString() ?? '';
      final parsedLines = (payload['parsedLines'] as int?) ?? lines.length;
      final ignoredLines = (payload['ignoredLines'] as int?) ?? 0;
      final serializedRules = (payload['rules'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<dynamic, dynamic>>();
      final rules = serializedRules
          .map((entry) => AdblockRule.fromJson(Map<String, dynamic>.from(entry)))
          .whereType<AdblockRule>()
          .toList(growable: false);
      if (revision.isEmpty || rules.isEmpty) {
        return _filterCompiler.compile(lines);
      }
      return FilterCompilationResult(
        rules: rules,
        revision: revision,
        parsedLines: parsedLines,
        ignoredLines: ignoredLines,
      );
    } catch (_) {
      return _filterCompiler.compile(lines);
    }
  }

  Future<AdblockDecision> evaluate(AdblockRequestContext context) async {
    if (_disposed) {
      return const AdblockDecision(blocked: false, reason: 'disposed');
    }
    if (!_initialized) {
      await initialize();
    }
    return _requestBlocker.evaluate(context);
  }

  void onMainFrameChanged(Uri? uri) {
    _metrics.onPageChanged(uri);
  }

  void updateConfig(AdblockConfig config, {bool reinitialize = false}) {
    _config = config;
    _logger.setEnabled(config.debugMode);
    _requestBlocker.setConfig(config);
    _requestBlocker.clearCache();
    if (reinitialize) {
      _initialized = false;
    }
  }

  void setEnabled(bool enabled) {
    if (_config.enabled == enabled) {
      return;
    }
    updateConfig(_config.copyWith(enabled: enabled));
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _engineAdapter.dispose();
    _requestBlocker.clearCache();
    _initialized = false;
    _activeRevision = '';
    _activeRuleCount = 0;
    _loadedSources = const <String>[];
    _usedCachedList = false;
    _logger.reset();
    _metrics.reset();
  }

  Future<List<AdblockRule>?> _tryLoadCompiledRulesCache({
    required String expectedRevision,
  }) async {
    final file = await _resolveCompiledRulesFile();
    if (!file.existsSync()) {
      return null;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final cachedRevision = decoded['revision']?.toString() ?? '';
      if (cachedRevision != expectedRevision) {
        return null;
      }
      final serializedRules =
          (decoded['rules'] as List<dynamic>? ?? const <dynamic>[])
              .cast<Map<dynamic, dynamic>>();
      final rules = serializedRules
          .map((entry) => AdblockRule.fromJson(Map<String, dynamic>.from(entry)))
          .whereType<AdblockRule>()
          .toList(growable: false);
      if (rules.isEmpty) {
        return null;
      }
      return rules;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCompiledRulesCache({
    required String revision,
    required List<AdblockRule> rules,
  }) async {
    final file = await _resolveCompiledRulesFile();
    final payload = <String, dynamic>{
      'revision': revision,
      'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  Future<File> _resolveCompiledRulesFile() async {
    final baseDirectory = await getApplicationSupportDirectory();
    final cacheDirectory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}$_cacheDirName',
    );
    if (!cacheDirectory.existsSync()) {
      await cacheDirectory.create(recursive: true);
    }
    return File(
      '${cacheDirectory.path}${Platform.pathSeparator}$_compiledRulesFileName',
    );
  }
}

Map<String, dynamic> _compileRulesWorker(Map<String, dynamic> payload) {
  final rawLines = (payload['lines'] as List<dynamic>? ?? const <dynamic>[])
      .map((entry) => entry.toString())
      .toList(growable: false);
  final compiler = const FilterCompiler();
  final result = compiler.compile(rawLines);
  return <String, dynamic>{
    'revision': result.revision,
    'parsedLines': result.parsedLines,
    'ignoredLines': result.ignoredLines,
    'rules': result.rules.map((rule) => rule.toJson()).toList(growable: false),
  };
}
