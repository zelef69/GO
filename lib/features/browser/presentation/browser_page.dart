import 'dart:convert';
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../app/config/app_config.dart';
import '../../../app/config/app_dependencies.dart';
import '../../../app/routes/app_routes.dart';
import '../../adblock/adblock_service.dart';
import '../../adblock/core/request_blocker.dart';
import '../../adblock/intercept/request_interceptor.dart';
import '../../auth/auth_controller.dart';
import '../../auth/domain/session_package_status.dart';
import '../../domain_lock/domain_policy_service.dart';
import '../../domain_lock/navigation_interceptor.dart';
import '../../pip/pip_controller.dart';
import '../../pip/pip_video_state.dart';
import '../../settings/settings_controller.dart';
import 'adblock_script.dart';
import 'background_playback_script.dart';
import 'pip_dom_script.dart';
import 'video_state_script.dart';
import 'widgets/browser_controls.dart';
import 'widgets/browser_error_view.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  final RequestInterceptor _requestInterceptor = const RequestInterceptor();

  late final NavigationInterceptor _navigationInterceptor;
  late final DomainPolicyService _domainPolicyService;
  late final AdblockService _adblockService;
  late final PiPController _pipController;
  late final SettingsController _settingsController;
  late final AuthController _authController;

  Timer? _packageTicker;
  SessionPackageStatus _packageStatus = SessionPackageStatus.fromExpiresAt(
    null,
  );
  bool _noPackageLockApplied = false;

  bool _isInitializing = true;
  bool _isLoading = true;
  bool _adblockRuntimeReady = false;
  int _progress = 0;
  bool _canGoBack = false;
  bool _videoPlaying = false;
  bool _videoFullscreen = false;
  int _videoWidth = 0;
  int _videoHeight = 0;
  int _videoRectLeft = 0;
  int _videoRectTop = 0;
  int _videoRectRight = 0;
  int _videoRectBottom = 0;
  String _mediaTitle = '';
  String _mediaAuthor = '';
  int _durationMs = 0;
  int _positionMs = 0;
  bool _hasNext = false;
  bool _isRequestingPiP = false;
  bool _isInPiPMode = false;
  bool _isPreparingPiPLayout = false;
  bool _pipRecoveryInProgress = false;
  int _pipRecoveryBudget = 0;
  bool _pauseRequestedByUserInPiP = false;
  bool _awaitingPiPExitRestore = false;
  bool _pipExitRestoreHandled = false;
  DateTime? _pipTransitionDeadline;
  int _pipPlayCommandCount = 0;
  DateTime? _lastPublishVideoStateAt;
  DateTime? _lastPiPLayoutHealthCheckAt;
  bool _isPublishingVideoState = false;
  bool _pipLayoutRepairInProgress = false;
  bool _isAppInForeground = true;
  bool _backgroundPlaybackGuardEnabled = false;
  static const Duration _pipTransitionWindow = Duration(milliseconds: 1500);
  static const Duration _videoStatePublishThrottle = Duration(
    milliseconds: 350,
  );
  static const Duration _pipLayoutHealthThrottle = Duration(milliseconds: 900);
  static const int _maxPiPRecoveryAttempts = 1;
  static const int _maxDnsAutoRetryAttempts = 1;
  static const Duration _dnsAutoRetryDelay = Duration(milliseconds: 450);
  static const Duration _slowPolicyCheckThreshold = Duration(milliseconds: 60);
  static const int _maxPolicyPerfLogs = 80;
  static const int _maxPlaybackDebugLogs = 500;
  static const int _maxVideoStateLogs = 500;
  static const int _maxAdblockTraceLogs = 2200;
  static const int _maxAdblockJsLogs = 2200;
  static const bool _enableVerboseAdblockTrace = bool.fromEnvironment(
    'GO_PLAY_ADBLOCK_TRACE',
    defaultValue: false,
  );
  static const bool _enableDocumentCspInjection = false;
  static const Duration _youtubeClickFallbackDelay = Duration(
    milliseconds: 260,
  );
  static const Duration _youtubeClickFallbackSettle = Duration(
    milliseconds: 90,
  );
  static const Duration _autoNextDelay = Duration(milliseconds: 280);
  static const Duration _autoNextStateSettle = Duration(milliseconds: 100);
  static const Duration _autoNextRetryDelay = Duration(milliseconds: 700);
  static const Duration _autoNextDuplicateWindow = Duration(seconds: 6);
  static const Duration _autoNextEndedDedupWindow = Duration(seconds: 4);
  static const Duration _scriptResyncThrottle = Duration(milliseconds: 650);
  static const Duration _navigationLogThrottle = Duration(milliseconds: 420);
  static const Duration _duplicateLoadStopWindow = Duration(milliseconds: 850);
  static const Duration _pipExitFallbackMinResumePosition = Duration(
    seconds: 30,
  );
  static const List<Duration> _pipExitCompactCheckDelays = <Duration>[
    Duration(milliseconds: 120),
    Duration(milliseconds: 350),
    Duration(milliseconds: 700),
  ];
  static const double _pipCompactWidthRatioThreshold = 0.70;
  PiPVideoState _pipState = PiPVideoState.empty();
  String? _errorMessage;
  String? _activeMainFrameRequestKey;
  int _dnsAutoRetryAttempt = 0;
  int _policyPerfLogCount = 0;
  int _playbackDebugLogCount = 0;
  int _videoStateLogCount = 0;
  int _adblockTraceLogCount = 0;
  int _adblockJsLogCount = 0;
  int _youtubePlayPauseClickToken = 0;
  int _pipExitNormalizationToken = 0;
  DateTime? _lastVideoStateScriptInjectAt;
  bool _isInjectingVideoStateScript = false;
  int _autoNextToken = 0;
  bool _autoNextPending = false;
  bool _autoNextTransitioning = false;
  String? _autoNextArmedVideoId;
  String? _autoNextArmedListId;
  String? _lastAutoNextVideoId;
  DateTime? _lastAutoNextTriggeredAt;
  String? _lastEndedAutoNextVideoId;
  DateTime? _lastEndedAutoNextAt;
  String? _lastEndedAutoNextSource;
  String _lastObservedVideoId = '';
  String _lastObservedListId = '';
  String _titleBoundVideoId = '';
  String? _lastPlaybackTickSignature;
  String? _lastVideoStateLogSignature;
  int _postAutoNextTitleRefreshToken = 0;
  String _lastInjectedCspSignature = '';
  Uri _currentMainFrameUri = AppConfig.homeUri;
  DateTime? _lastNavigationLogAt;
  String _lastNavigationLogSignature = '';
  DateTime? _lastLoadStopHandledAt;
  String _lastLoadStopHandledKey = '';
  DateTime? _lastAdblockScriptSyncAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _navigationInterceptor = widget.dependencies.navigationInterceptor;
    _domainPolicyService = widget.dependencies.domainPolicyService;
    _adblockService = widget.dependencies.adblockService;
    _pipController = widget.dependencies.pipController;
    _settingsController = widget.dependencies.settingsController;
    _authController = widget.dependencies.authController;
    _settingsController.addListener(_onSettingsChanged);
    _authController.addListener(_onAuthSessionChanged);
    _pipController.setMethodCallHandler(_onNativePiPEvent);
    _syncPackageStatus();
    _packageTicker = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _syncPackageStatus(),
    );
    unawaited(_bootstrap());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inForeground = state == AppLifecycleState.resumed;
    _isAppInForeground = inForeground;
    _logPiPEvent(
      'lifecycle state=$state inForeground=$inForeground inPiP=$_isInPiPMode playing=$_videoPlaying bgEnabled=${_settingsController.backgroundPlaybackEnabled} guard=$_backgroundPlaybackGuardEnabled',
    );
    unawaited(_pipController.setAppInForeground(inForeground));
    if (state == AppLifecycleState.resumed) {
      unawaited(
        _setBackgroundPlaybackGuardEnabled(false, reason: 'lifecycle_resumed'),
      );
      unawaited(_adblockService.onAppResumed());
      _adblockService.scheduleCrowdSync(reason: 'app_resumed');
      unawaited(_handleAppResumedLifecycle());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_syncBackgroundPlaybackGuard(reason: 'lifecycle_$state'));
    }
  }

  @override
  void dispose() {
    _cancelPendingAutoNext(reason: 'dispose');
    _setAutoNextTransitioning(false, reason: 'dispose');
    _resetPiPRecoveryState();
    WidgetsBinding.instance.removeObserver(this);
    _settingsController.removeListener(_onSettingsChanged);
    _authController.removeListener(_onAuthSessionChanged);
    _packageTicker?.cancel();
    _packageTicker = null;
    unawaited(_pipController.setAppInForeground(false));
    _pipController.setMethodCallHandler(null);
    unawaited(_adblockService.dispose());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      _adblockService.setEnabled(_settingsController.adblockEnabled);
      try {
        await _adblockService.initialize();
        _adblockService.scheduleCrowdSync(reason: 'browser_bootstrap');
      } catch (error) {
        _logAdblockTrace('bootstrap adblock initialize error=$error');
      }
      try {
        await _pipController.initialize(
          pipEnabled: _settingsController.pipEnabled,
          backgroundPlaybackEnabled:
              _settingsController.backgroundPlaybackEnabled,
        );
      } catch (error) {
        _logPiPEvent('bootstrap pip initialize error=$error');
      }
    } catch (error) {
      _logPiPEvent('bootstrap unexpected error=$error');
    } finally {
      if (mounted) {
        setState(() {
          _errorMessage = null;
          _isInitializing = false;
        });
      }
    }
  }

  void _onSettingsChanged() {
    _adblockService.setEnabled(_settingsController.adblockEnabled);
    unawaited(_pipController.setPiPEnabled(_settingsController.pipEnabled));
    unawaited(
      _pipController.setBackgroundPlaybackEnabled(
        _settingsController.backgroundPlaybackEnabled,
      ),
    );
    unawaited(_syncAdblockScript(force: true));
    unawaited(_syncBackgroundPlaybackGuard(reason: 'settings_changed'));
  }

  void _onAuthSessionChanged() {
    _syncPackageStatus();
  }

  void _syncPackageStatus() {
    final nextStatus = SessionPackageStatus.fromExpiresAt(
      _authController.currentSubscription?.expiryDate,
    );
    if (nextStatus.remainingDays == _packageStatus.remainingDays &&
        nextStatus.hasPackage == _packageStatus.hasPackage &&
        nextStatus.expiresAtUtc == _packageStatus.expiresAtUtc) {
      return;
    }

    if (mounted) {
      setState(() {
        _packageStatus = nextStatus;
      });
    } else {
      _packageStatus = nextStatus;
    }

    if (!nextStatus.hasPackage) {
      if (!_noPackageLockApplied) {
        _noPackageLockApplied = true;
        unawaited(_enforceNoPackageLockdown());
      }
    } else {
      _noPackageLockApplied = false;
    }
  }

  Future<void> _enforceNoPackageLockdown() async {
    await _pauseVideoInWebView();
    await _setBackgroundPlaybackGuardEnabled(
      false,
      reason: 'no_package_lockdown',
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('NO PACKAGE: กรุณาต่ออายุเพื่อใช้งานต่อ')),
      );
  }

  bool _ensurePackageEnabled() {
    if (_packageStatus.hasPackage) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('แพ็กเกจหมดอายุ: ไม่สามารถใช้งานฟีเจอร์ได้'),
        ),
      );
    return false;
  }

  Uri? _toUri(WebUri? webUri) {
    if (webUri == null) {
      return null;
    }
    return Uri.tryParse(webUri.toString());
  }

  Uri? _sourceUriFromRequest(WebResourceRequest request) {
    return _sourceUriFromHeaders(request.headers);
  }

  Uri? _sourceUriFromHeaders(Map<String, dynamic>? headers) {
    return _requestInterceptor.sourceUriFromHeaders(headers);
  }

  bool _isYouTubeHost(String host) {
    final normalizedHost = host.toLowerCase();
    return normalizedHost == 'youtube.com' ||
        normalizedHost == 'm.youtube.com' ||
        normalizedHost.endsWith('.youtube.com');
  }

  bool _isGoogleVideoPlaybackUri(Uri uri) {
    final normalizedHost = uri.host.toLowerCase();
    final isGoogleVideoHost =
        normalizedHost == 'googlevideo.com' ||
        normalizedHost.endsWith('.googlevideo.com');
    return isGoogleVideoHost &&
        uri.path.toLowerCase().contains('/videoplayback');
  }

  bool _isGenericBrowseSourcePath(Uri sourceUri) {
    final path = sourceUri.path.toLowerCase();
    if (path.isEmpty || path == '/') {
      return true;
    }
    return path.startsWith('/results') ||
        path == '/feed' ||
        path.startsWith('/feed/');
  }

  Uri? _synthesizeWatchSourceWhenHeaderMissing({
    required Uri requestUri,
    required Uri sourceUri,
  }) {
    if (!_isGoogleVideoPlaybackUri(requestUri)) {
      return null;
    }
    if (!_isYouTubeHost(sourceUri.host)) {
      return null;
    }
    if (!_isGenericBrowseSourcePath(sourceUri)) {
      return null;
    }
    final videoId = _currentKnownVideoId().trim();
    if (videoId.isEmpty) {
      return null;
    }
    final queryParameters = <String, String>{'v': videoId};
    final listId = _currentKnownListId().trim();
    if (listId.isNotEmpty) {
      queryParameters['list'] = listId;
    }
    return sourceUri.replace(
      path: '/watch',
      queryParameters: queryParameters,
      fragment: '',
    );
  }

  String? _mainFrameRequestKey(Uri? uri) {
    if (uri == null) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    return '$scheme://$host${uri.path}?${uri.query}';
  }

  void _rememberMainFrameUri(Uri? uri) {
    if (uri == null) {
      return;
    }
    if (uri.scheme.isEmpty || uri.host.isEmpty) {
      return;
    }
    _currentMainFrameUri = uri;
    _adblockService.onMainFrameChanged(uri);
    final observedVideoId = _videoIdFromUri(uri);
    if (observedVideoId.isNotEmpty) {
      _lastObservedVideoId = observedVideoId;
    }
    _lastObservedListId = _listIdFromUri(uri);
  }

  void _markMainFrameNavigation(Uri? uri, {required bool resetRetryBudget}) {
    _rememberMainFrameUri(uri);
    final key = _mainFrameRequestKey(uri);
    if (key == null) {
      return;
    }
    if (_activeMainFrameRequestKey != key) {
      _activeMainFrameRequestKey = key;
      _dnsAutoRetryAttempt = 0;
      return;
    }
    if (resetRetryBudget) {
      _dnsAutoRetryAttempt = 0;
    }
  }

  bool _isSkippableNonAdPolicyRequest(Uri uri, {required String resourceType}) {
    final normalizedType = resourceType.toLowerCase();
    if (normalizedType == 'document' || normalizedType == 'subdocument') {
      return false;
    }

    final host = uri.host.toLowerCase();
    final isYouTubeHost =
        host == 'youtube.com' || host.endsWith('.youtube.com');
    if (!isYouTubeHost) {
      return false;
    }

    final path = uri.path.toLowerCase();
    if (path == '/favicon.ico' || path == '/static/favicon.ico') {
      return true;
    }
    if (path.startsWith('/s/search/audio/')) {
      return true;
    }
    if (path == '/api/stats/watchtime' || path == '/api/stats/qoe') {
      return true;
    }
    if ((normalizedType == 'script' || normalizedType == 'stylesheet') &&
        (path.startsWith('/s/_/ytmweb/_/js/') ||
            path.startsWith('/s/_/ytmweb/_/ss/') ||
            path.startsWith('/s/player/'))) {
      return true;
    }
    return false;
  }

  bool _isDnsResolveError(WebResourceError error) {
    final description = error.description.toLowerCase();
    if (description.contains('err_name_not_resolved') ||
        description.contains('name_not_resolved') ||
        description.contains('name not resolved')) {
      return true;
    }
    return error.type.toValue() == WebResourceErrorType.HOST_LOOKUP.toValue();
  }

  bool _shouldSkipDuplicateLoadStop(Uri? uri) {
    final key = _mainFrameRequestKey(uri);
    if (key == null || key.isEmpty) {
      return false;
    }
    final now = DateTime.now();
    final lastHandledAt = _lastLoadStopHandledAt;
    final isDuplicate =
        _lastLoadStopHandledKey == key &&
        lastHandledAt != null &&
        now.difference(lastHandledAt) < _duplicateLoadStopWindow;
    if (!isDuplicate) {
      _lastLoadStopHandledKey = key;
      _lastLoadStopHandledAt = now;
    }
    return isDuplicate;
  }

  Future<void> _autoRetryAfterDnsError(Uri? failedUri) async {
    final controller = _webViewController;
    if (controller == null) {
      return;
    }
    _dnsAutoRetryAttempt += 1;
    if (mounted) {
      setState(() {
        _errorMessage = null;
        _isLoading = true;
      });
    }
    await Future<void>.delayed(_dnsAutoRetryDelay);
    if (!mounted) {
      return;
    }
    final currentUri = _toUri(await controller.getUrl());
    final targetUri = failedUri ?? currentUri ?? AppConfig.homeUri;
    _rememberMainFrameUri(targetUri);
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(targetUri.toString())),
    );
  }

  Future<AdblockDecision> _shouldBlockByPolicyAndAdblock(
    InAppWebViewController controller,
    Uri uri, {
    required String resourceType,
    Uri? sourceUri,
  }) async {
    final totalWatch = Stopwatch()..start();
    if (!_domainPolicyService.isRequestAllowed(uri)) {
      return AdblockDecision(
        blocked: true,
        reason: 'domain_policy',
        matchedRule: uri.host,
      );
    }

    final normalizedType = resourceType.toLowerCase();
    // Keep top-level/sub-frame documents stable. Domain policy already protects
    // forbidden hosts, so adblock network matcher can skip these to avoid
    // accidental page breakage.
    if (normalizedType == 'document' || normalizedType == 'subdocument') {
      return const AdblockDecision(
        blocked: false,
        reason: 'document_pass_through',
      );
    }

    if (uri.scheme.toLowerCase() != 'https') {
      return const AdblockDecision(blocked: false, reason: 'non_https');
    }

    if (_isSkippableNonAdPolicyRequest(uri, resourceType: resourceType)) {
      return const AdblockDecision(blocked: false, reason: 'static_fast_path');
    }

    var sourceLookupDuration = Duration.zero;
    final missingSourceHeader = sourceUri == null;
    var sourceKind = 'request.header';
    Uri effectiveSource;
    if (sourceUri != null) {
      effectiveSource = sourceUri;
    } else if (_currentMainFrameUri.host.isNotEmpty) {
      effectiveSource = _currentMainFrameUri;
      sourceKind = 'mainframe.cache';
    } else {
      sourceKind = 'webview.getUrl';
      final sourceWatch = Stopwatch()..start();
      effectiveSource = _toUri(await controller.getUrl()) ?? AppConfig.homeUri;
      sourceWatch.stop();
      sourceLookupDuration = sourceWatch.elapsed;
      _rememberMainFrameUri(effectiveSource);
    }
    if (missingSourceHeader) {
      final synthesizedSource = _synthesizeWatchSourceWhenHeaderMissing(
        requestUri: uri,
        sourceUri: effectiveSource,
      );
      if (synthesizedSource != null) {
        effectiveSource = synthesizedSource;
        sourceKind = '$sourceKind.synthetic_watch';
      }
    }

    final adblockWatch = Stopwatch()..start();
    final signalKey = _adblockService.resolveRequestSignalKey(
      uri,
      sourceUrl: effectiveSource,
    );
    final adShowing = _adblockService.isAdSignalActiveForRequest(
      uri,
      sourceUrl: effectiveSource,
    );
    final playbackStalled = _adblockService.isPlaybackStalledForRequest(
      uri,
      sourceUrl: effectiveSource,
    );
    final adblockDecision = await _adblockService.evaluateRequest(
      uri,
      resourceType: resourceType,
      sourceUrl: effectiveSource,
      adShowing: adShowing,
      playbackStalled: playbackStalled,
      adSignalKey: signalKey,
    );
    final blocked = adblockDecision.blocked;
    adblockWatch.stop();
    totalWatch.stop();

    if (kDebugMode &&
        _policyPerfLogCount < _maxPolicyPerfLogs &&
        (blocked || totalWatch.elapsed >= _slowPolicyCheckThreshold)) {
      _policyPerfLogCount += 1;
      debugPrint(
        '[GO_PLAY-Perf] policy uri=${uri.host}${uri.path} type=$resourceType blocked=$blocked action=${adblockDecision.effectiveAction.name} reason=${adblockDecision.reason} adSignal=$adShowing stalled=$playbackStalled signalKey=$signalKey candidates=${adblockDecision.candidateCount} evaluated=${adblockDecision.evaluatedCount} totalMs=${totalWatch.elapsedMilliseconds} sourceMs=${sourceLookupDuration.inMilliseconds} adblockMs=${adblockWatch.elapsedMilliseconds} source=$sourceKind',
      );
    }

    return adblockDecision;
  }

  Future<void> _applyDocumentCspIfNeeded(Uri? pageUri) async {
    if (!_enableDocumentCspInjection) {
      return;
    }
    final controller = _webViewController;
    if (controller == null || pageUri == null || pageUri.host.isEmpty) {
      return;
    }
    final directives = await _adblockService.getCspDirectives(
      pageUri,
      resourceType: 'document',
      sourceUrl: pageUri,
    );
    final normalized = (directives ?? '').trim();
    if (normalized.isEmpty) {
      return;
    }
    final signature = '${pageUri.host}${pageUri.path}|$normalized';
    if (signature == _lastInjectedCspSignature) {
      return;
    }
    final escaped = normalized
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', ' ');
    final script =
        '''
(function() {
  try {
    if (document.querySelector('meta[data-go-play-csp="1"]')) {
      return;
    }
    var meta = document.createElement('meta');
    meta.httpEquiv = 'Content-Security-Policy';
    meta.content = '$escaped';
    meta.setAttribute('data-go-play-csp', '1');
    if (document.head) {
      document.head.appendChild(meta);
    } else {
      document.documentElement.appendChild(meta);
    }
  } catch (_) {}
})();
''';
    try {
      await controller.evaluateJavascript(source: script);
      _lastInjectedCspSignature = signature;
      _logAdblockTrace(
        'document csp injected host=${pageUri.host} directivesLen=${normalized.length}',
      );
    } catch (_) {}
  }

  Future<AjaxRequest?> _interceptAjaxRequest(
    InAppWebViewController controller,
    AjaxRequest ajaxRequest,
  ) async {
    final uri = _toUri(ajaxRequest.url);
    if (uri == null) {
      return ajaxRequest;
    }

    final sourceUri = _sourceUriFromHeaders(ajaxRequest.headers?.getHeaders());
    final resourceType = _resourceTypeForAjaxLikeRequest(uri);
    final decision = await _shouldBlockByPolicyAndAdblock(
      controller,
      uri,
      resourceType: resourceType,
      sourceUri: sourceUri,
    );
    final redirectDataUrl = (decision.redirectDataUrl ?? '').trim();
    if (redirectDataUrl.isNotEmpty) {
      ajaxRequest.url = WebUri(redirectDataUrl);
      ajaxRequest.action = AjaxRequestAction.PROCEED;
      _logAdblockTrace(
        'ajax redirect-data reason=${decision.reason} from=${uri.host}${uri.path}',
      );
      return ajaxRequest;
    }
    final rewrittenUrl = (decision.rewrittenUrl ?? '').trim();
    if (rewrittenUrl.isNotEmpty) {
      final parsedRewritten = Uri.tryParse(rewrittenUrl);
      if (parsedRewritten != null &&
          parsedRewritten.scheme.isNotEmpty &&
          parsedRewritten.host.isNotEmpty) {
        ajaxRequest.url = WebUri(rewrittenUrl);
        _logAdblockTrace(
          'ajax rewrite reason=${decision.reason} from=${uri.host}${uri.path} to=${parsedRewritten.host}${parsedRewritten.path}',
        );
      }
    }
    if (decision.blocked) {
      ajaxRequest.action = AjaxRequestAction.ABORT;
    }
    return ajaxRequest;
  }

  Future<FetchRequest?> _interceptFetchRequest(
    InAppWebViewController controller,
    FetchRequest fetchRequest,
  ) async {
    final uri = _toUri(fetchRequest.url);
    if (uri == null) {
      return fetchRequest;
    }

    final sourceUri = _sourceUriFromHeaders(fetchRequest.headers);
    final resourceType = _resourceTypeForAjaxLikeRequest(uri);
    final decision = await _shouldBlockByPolicyAndAdblock(
      controller,
      uri,
      resourceType: resourceType,
      sourceUri: sourceUri,
    );
    final redirectDataUrl = (decision.redirectDataUrl ?? '').trim();
    if (redirectDataUrl.isNotEmpty) {
      fetchRequest.url = WebUri(redirectDataUrl);
      fetchRequest.action = FetchRequestAction.PROCEED;
      _logAdblockTrace(
        'fetch redirect-data reason=${decision.reason} from=${uri.host}${uri.path}',
      );
      return fetchRequest;
    }
    final rewrittenUrl = (decision.rewrittenUrl ?? '').trim();
    if (rewrittenUrl.isNotEmpty) {
      final parsedRewritten = Uri.tryParse(rewrittenUrl);
      if (parsedRewritten != null &&
          parsedRewritten.scheme.isNotEmpty &&
          parsedRewritten.host.isNotEmpty) {
        fetchRequest.url = WebUri(rewrittenUrl);
        _logAdblockTrace(
          'fetch rewrite reason=${decision.reason} from=${uri.host}${uri.path} to=${parsedRewritten.host}${parsedRewritten.path}',
        );
      }
    }
    if (decision.blocked) {
      fetchRequest.action = FetchRequestAction.ABORT;
    }
    return fetchRequest;
  }

  String _resourceTypeForAjaxLikeRequest(Uri uri) {
    if (_isGoogleVideoPlaybackUri(uri)) {
      return 'media';
    }
    return 'xmlhttprequest';
  }

  String _resourceTypeFromRequest(WebResourceRequest request, Uri uri) {
    return _requestInterceptor.classifyResourceType(
      url: uri,
      isMainFrame: request.isForMainFrame == true,
      headers: request.headers,
    );
  }

  String _navigationBlockReasonLabel(NavigationBlockReason? reason) {
    switch (reason) {
      case NavigationBlockReason.invalidUrl:
        return 'invalid URL';
      case NavigationBlockReason.unsafeScheme:
        return 'unsafe scheme';
      case NavigationBlockReason.disallowedHost:
        return 'external domain';
      case null:
        return 'policy';
    }
  }

  void _showBlockedNavigation(Uri? uri, NavigationBlockReason? reason) {
    final host = uri?.host.isNotEmpty == true
        ? uri!.host
        : (uri?.toString() ?? 'unknown');
    final message =
        'Blocked navigation to $host (${_navigationBlockReasonLabel(reason)})';
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _logNavigationEvent(String event, Uri? uri) {
    if (!kDebugMode) {
      return;
    }
    final label = uri == null ? 'unknown' : '${uri.host}${uri.path}';
    final signature = '$event|$label';
    final now = DateTime.now();
    final lastAt = _lastNavigationLogAt;
    if (signature == _lastNavigationLogSignature &&
        lastAt != null &&
        now.difference(lastAt) < _navigationLogThrottle) {
      return;
    }
    _lastNavigationLogSignature = signature;
    _lastNavigationLogAt = now;
    debugPrint('[GO_PLAY-Nav] $event url=$label');
  }

  void _logAdblockTrace(String message) {
    if (!kDebugMode ||
        !_enableVerboseAdblockTrace ||
        _adblockTraceLogCount >= _maxAdblockTraceLogs) {
      return;
    }
    _adblockTraceLogCount += 1;
    debugPrint('[GO_PLAY-Adblock][Trace][TH] $message');
  }

  void _logAdblockJsPayload(Map<String, dynamic> payload) {
    if (!kDebugMode || _adblockJsLogCount >= _maxAdblockJsLogs) {
      return;
    }
    final seq = _toInt(payload['seq']);
    final event = (payload['event'] ?? '').toString().trim();
    final reason = (payload['reason'] ?? '').toString().trim();
    final host = (payload['host'] ?? '').toString().trim();
    final path = (payload['path'] ?? '').toString().trim();
    final type = (payload['resourceType'] ?? '').toString().trim();
    final blocked = payload['blocked'] == true;
    final clicks = _toInt(payload['clicks']);
    final noProgressMs = _toInt(payload['noProgressMs']);
    final recoverCount = _toInt(payload['recoverCount']);
    final page = (payload['pageVisibility'] ?? '').toString().trim();
    final criticalEvent =
        blocked ||
        event.toLowerCase().startsWith('anti_adblock') ||
        reason.toLowerCase().contains('anti_adblock');
    if (!_enableVerboseAdblockTrace && !criticalEvent) {
      return;
    }
    _adblockJsLogCount += 1;
    debugPrint(
      '[GO_PLAY-Adblock][JS][TH] ลำดับ=$seq เหตุการณ์=$event เหตุผล=$reason โฮสต์=$host พาธ=$path ประเภท=$type บล็อก=$blocked คลิก=$clicks ค้างMs=$noProgressMs จำนวนกู้คืน=$recoverCount หน้า=$page',
    );
  }

  Future<void> _updateCanGoBack() async {
    final controller = _webViewController;
    if (controller == null) {
      return;
    }

    final canGoBack = await controller.canGoBack();
    if (mounted && canGoBack != _canGoBack) {
      setState(() {
        _canGoBack = canGoBack;
      });
    }
  }

  int _toPositiveInt(dynamic value) {
    if (value is int) {
      return value > 0 ? value : 0;
    }
    if (value is num) {
      final rounded = value.round();
      return rounded > 0 ? rounded : 0;
    }
    return 0;
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return 0;
  }

  double _toPositiveDouble(dynamic value) {
    if (value is num) {
      final asDouble = value.toDouble();
      return asDouble > 0 ? asDouble : 0;
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return 0;
  }

  Map<String, dynamic> _asStringDynamicMap(dynamic value) {
    dynamic current = value;
    for (var depth = 0; depth < 2; depth += 1) {
      if (current is Map) {
        return current.map<String, dynamic>(
          (dynamic key, dynamic mapValue) =>
              MapEntry<String, dynamic>(key.toString(), mapValue),
        );
      }
      if (current is! String) {
        break;
      }
      final raw = current.trim();
      if (raw.isEmpty || raw == 'null') {
        return const <String, dynamic>{};
      }
      try {
        current = jsonDecode(raw);
      } catch (_) {
        break;
      }
    }
    return const <String, dynamic>{};
  }

  void _logPiPEvent(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('GoPlayPiPFlutter $message');
  }

  void _logPlaybackDebugPayload(Map<String, dynamic> payload) {
    if (!kDebugMode || _playbackDebugLogCount >= _maxPlaybackDebugLogs) {
      return;
    }

    final eventName = (payload['event'] ?? '').toString();
    final videoId = (payload['videoId'] ?? '').toString();
    final adShowing = payload['adShowing'] == true;
    final adInterrupting = payload['adInterrupting'] == true;
    final hasAdOverlay = payload['hasAdOverlay'] == true;
    final spinnerVisible = payload['spinnerVisible'] == true;
    final hasVideo = payload['hasVideo'] == true;
    final paused = payload['paused'] == true;
    final videoVisible = payload['videoVisible'] == true;
    final readyState = _toInt(payload['readyState']);
    final networkState = _toInt(payload['networkState']);
    final currentTimeMs = _toPositiveInt(payload['currentTimeMs']);
    final bufferedAheadMs = _toPositiveInt(payload['bufferedAheadMs']);
    final videoWidth = _toPositiveInt(payload['videoWidth']);
    final videoHeight = _toPositiveInt(payload['videoHeight']);
    final cssWidth = _toPositiveInt(payload['cssWidth']);
    final cssHeight = _toPositiveInt(payload['cssHeight']);
    final pageVisibility = (payload['pageVisibility'] ?? '').toString();

    final rawUrl = (payload['url'] ?? '').toString();
    final parsedUrl = Uri.tryParse(rawUrl);
    final urlSummary = parsedUrl == null
        ? rawUrl
        : (() {
            final vidParam = parsedUrl.queryParameters['v'];
            final suffix = vidParam == null || vidParam.isEmpty
                ? ''
                : '?v=$vidParam';
            return '${parsedUrl.host}${parsedUrl.path}$suffix';
          })();

    final tickSignature =
        '$videoId|$adShowing|$adInterrupting|$hasAdOverlay|$spinnerVisible|$hasVideo|$paused|$videoVisible|$readyState|$networkState|$currentTimeMs|$bufferedAheadMs|$videoWidth|$videoHeight|$cssWidth|$cssHeight|$pageVisibility';
    if (eventName == 'tick' && tickSignature == _lastPlaybackTickSignature) {
      return;
    }
    _lastPlaybackTickSignature = tickSignature;

    _playbackDebugLogCount += 1;
    debugPrint(
      '[GO_PLAY-Playback] ev=$eventName vid=$videoId ad=$adShowing/$adInterrupting overlay=$hasAdOverlay spinner=$spinnerVisible hasVideo=$hasVideo paused=$paused ready=$readyState net=$networkState tMs=$currentTimeMs bufMs=$bufferedAheadMs visible=$videoVisible px=${videoWidth}x$videoHeight css=${cssWidth}x$cssHeight page=$pageVisibility url=$urlSummary',
    );
  }

  void _logVideoStatePayload(
    Map<String, dynamic> payload, {
    required String source,
  }) {
    if (!kDebugMode || _videoStateLogCount >= _maxVideoStateLogs) {
      return;
    }

    final eventName = (payload['event'] ?? 'snapshot').toString().trim();
    final pageVisibility = (payload['pageVisibility'] ?? 'unknown')
        .toString()
        .trim()
        .toLowerCase();
    final videoId = (payload['videoId'] ?? '').toString().trim();
    final isPlaying = payload['isPlaying'] == true;
    final isFullscreen = payload['isFullscreen'] == true;
    final paused = payload['paused'] == true;
    final ended = payload['ended'] == true;
    final readyState = _toInt(payload['readyState']);
    final durationMs = _toPositiveInt(payload['durationMs']);
    final positionMs = _toPositiveInt(payload['positionMs']);
    final hasNext = payload['hasNext'] == true;
    final title = (payload['title'] ?? '').toString().trim();
    final compactTitle = title.length > 60
        ? '${title.substring(0, 60)}...'
        : title;

    final signature =
        '$source|$eventName|$pageVisibility|$videoId|$isPlaying|$isFullscreen|$paused|$ended|$readyState|$positionMs|$durationMs|$hasNext|$compactTitle';
    if (signature == _lastVideoStateLogSignature) {
      return;
    }
    _lastVideoStateLogSignature = signature;

    _videoStateLogCount += 1;
    debugPrint(
      '[GO_PLAY-VideoState] src=$source ev=$eventName page=$pageVisibility vid=$videoId playing=$isPlaying paused=$paused ended=$ended ready=$readyState fullscreen=$isFullscreen posMs=$positionMs durMs=$durationMs hasNext=$hasNext title=$compactTitle',
    );
  }

  String _videoIdFromDebugPayload(Map<String, dynamic> payload) {
    final directVideoId = (payload['videoId'] ?? '').toString().trim();
    if (directVideoId.isNotEmpty) {
      return directVideoId;
    }

    final rawUrl = (payload['url'] ?? '').toString().trim();
    final parsedUrl = Uri.tryParse(rawUrl);
    if (parsedUrl == null) {
      return '';
    }
    final queryVideoId = (parsedUrl.queryParameters['v'] ?? '').trim();
    if (queryVideoId.isNotEmpty) {
      return queryVideoId;
    }
    final segments = parsedUrl.pathSegments;
    final shortsIndex = segments.indexOf('shorts');
    if (shortsIndex >= 0 && segments.length > shortsIndex + 1) {
      return segments[shortsIndex + 1].trim();
    }
    return '';
  }

  bool _isShortsUrlFromDebugPayload(Map<String, dynamic> payload) {
    final rawUrl = (payload['url'] ?? '').toString().trim();
    final parsedUrl = Uri.tryParse(rawUrl);
    if (parsedUrl == null) {
      return false;
    }
    return parsedUrl.path.toLowerCase().startsWith('/shorts/');
  }

  String _listIdFromDebugPayload(Map<String, dynamic> payload) {
    final rawUrl = (payload['url'] ?? '').toString().trim();
    final parsedUrl = Uri.tryParse(rawUrl);
    if (parsedUrl == null) {
      return '';
    }
    return (parsedUrl.queryParameters['list'] ?? '').trim();
  }

  bool _hasListContextFromDebugPayload(Map<String, dynamic> payload) {
    return _listIdFromDebugPayload(payload).isNotEmpty;
  }

  String _videoIdFromUri(Uri? uri) {
    if (uri == null) {
      return '';
    }
    final queryVideoId = (uri.queryParameters['v'] ?? '').trim();
    if (queryVideoId.isNotEmpty) {
      return queryVideoId;
    }
    final segments = uri.pathSegments;
    final shortsIndex = segments.indexOf('shorts');
    if (shortsIndex >= 0 && segments.length > shortsIndex + 1) {
      return segments[shortsIndex + 1].trim();
    }
    return '';
  }

  String _listIdFromUri(Uri? uri) {
    if (uri == null) {
      return '';
    }
    return (uri.queryParameters['list'] ?? '').trim();
  }

  String _currentKnownVideoId() {
    if (_lastObservedVideoId.isNotEmpty) {
      return _lastObservedVideoId;
    }
    return _videoIdFromUri(_currentMainFrameUri);
  }

  String _currentKnownListId() {
    if (_lastObservedListId.isNotEmpty) {
      return _lastObservedListId;
    }
    return _listIdFromUri(_currentMainFrameUri);
  }

  String _normalizeVideoTitle(String raw) {
    var normalized = raw.trim();
    if (normalized.isEmpty) {
      return '';
    }
    normalized = normalized.replaceFirst(
      RegExp(r'\s*-\s*YouTube\s*$', caseSensitive: false),
      '',
    );
    final lower = normalized.toLowerCase();
    if (lower == 'youtube' || lower == 'youtube music') {
      return '';
    }
    return normalized.trim();
  }

  String _resolvedVideoTitle({
    required String title,
    required String videoId,
    String fallbackTitle = '',
  }) {
    final normalizedTitle = _normalizeVideoTitle(title);
    if (normalizedTitle.isNotEmpty) {
      return normalizedTitle;
    }
    final normalizedFallbackTitle = _normalizeVideoTitle(fallbackTitle);
    if (normalizedFallbackTitle.isEmpty) {
      return '';
    }

    final normalizedVideoId = videoId.trim();
    final boundVideoId = _titleBoundVideoId.trim();
    final canReuseFallbackTitle =
        normalizedVideoId.isEmpty ||
        boundVideoId.isEmpty ||
        normalizedVideoId == boundVideoId;
    if (!canReuseFallbackTitle) {
      return '';
    }
    return normalizedFallbackTitle;
  }

  void _syncMediaMetadataFromDebugPayload(Map<String, dynamic> payload) {
    final payloadVideoId = _videoIdFromDebugPayload(payload).trim();
    final nextTitle = _resolvedVideoTitle(
      title: (payload['title'] ?? '').toString(),
      videoId: payloadVideoId,
      fallbackTitle: _mediaTitle,
    );
    final previousBoundVideoId = _titleBoundVideoId.trim();
    final videoChanged =
        payloadVideoId.isNotEmpty &&
        previousBoundVideoId.isNotEmpty &&
        payloadVideoId != previousBoundVideoId;
    final payloadAuthor = (payload['author'] ?? '').toString().trim();
    var nextAuthor = payloadAuthor.isNotEmpty ? payloadAuthor : _mediaAuthor;
    if (nextTitle.isEmpty && videoChanged) {
      nextAuthor = '';
    }
    final nextBoundVideoId = nextTitle.isNotEmpty
        ? (payloadVideoId.isNotEmpty ? payloadVideoId : previousBoundVideoId)
        : '';
    if (nextTitle == _mediaTitle &&
        nextAuthor == _mediaAuthor &&
        nextBoundVideoId == _titleBoundVideoId) {
      return;
    }
    if (mounted) {
      setState(() {
        _mediaTitle = nextTitle;
        _mediaAuthor = nextAuthor;
        _titleBoundVideoId = nextBoundVideoId;
      });
    } else {
      _mediaTitle = nextTitle;
      _mediaAuthor = nextAuthor;
      _titleBoundVideoId = nextBoundVideoId;
    }
    _pipState = _pipState.copyWith(title: nextTitle, author: nextAuthor);
    unawaited(_pipController.updateState(_pipState));
  }

  void _cancelPendingAutoNext({required String reason}) {
    if (!_autoNextPending) {
      return;
    }
    final armedVideoId = _autoNextArmedVideoId ?? '';
    final armedListId = _autoNextArmedListId ?? '';
    _autoNextToken += 1;
    _autoNextPending = false;
    _autoNextArmedVideoId = null;
    _autoNextArmedListId = null;
    _logPiPEvent(
      'autoNext cancel reason=$reason videoId=$armedVideoId listId=$armedListId',
    );
    _setAutoNextTransitioning(false, reason: 'cancel_$reason');
  }

  void _setAutoNextTransitioning(bool transitioning, {required String reason}) {
    if (_autoNextTransitioning == transitioning) {
      return;
    }
    if (mounted) {
      setState(() {
        _autoNextTransitioning = transitioning;
      });
    } else {
      _autoNextTransitioning = transitioning;
    }
    _logPiPEvent('autoNext transition=$transitioning reason=$reason');
  }

  void _schedulePostAutoNextTitleRefresh({required String reason}) {
    final token = ++_postAutoNextTitleRefreshToken;
    unawaited(_runPostAutoNextTitleRefresh(token: token, reason: reason));
  }

  Future<void> _runPostAutoNextTitleRefresh({
    required int token,
    required String reason,
  }) async {
    await _publishVideoStateNow(force: true);
    for (final delay in const <Duration>[
      Duration(milliseconds: 250),
      Duration(milliseconds: 650),
    ]) {
      await Future<void>.delayed(delay);
      if (!mounted || token != _postAutoNextTitleRefreshToken) {
        return;
      }
      await _publishVideoStateNow(force: true);
    }
    _logPiPEvent('titleRefresh done reason=$reason token=$token');
  }

  bool _isDuplicateEndedAutoNext({
    required String videoId,
    required String source,
  }) {
    if (videoId.isEmpty) {
      return false;
    }
    final lastVideoId = (_lastEndedAutoNextVideoId ?? '').trim();
    final lastAt = _lastEndedAutoNextAt;
    if (lastVideoId.isEmpty || lastAt == null) {
      return false;
    }
    final withinWindow =
        DateTime.now().difference(lastAt) < _autoNextEndedDedupWindow;
    if (!withinWindow) {
      return false;
    }
    if (lastVideoId != videoId) {
      return false;
    }
    _logPiPEvent(
      'autoNext dedup skip source=$source videoId=$videoId lastSource=${_lastEndedAutoNextSource ?? ''}',
    );
    return true;
  }

  void _markEndedAutoNext({required String videoId, required String source}) {
    if (videoId.isEmpty) {
      return;
    }
    _lastEndedAutoNextVideoId = videoId;
    _lastEndedAutoNextAt = DateTime.now();
    _lastEndedAutoNextSource = source;
    _logPiPEvent('autoNext dedup mark source=$source videoId=$videoId');
  }

  void _scheduleAutoNextFromEnded(Map<String, dynamic> payload) {
    final adShowing = payload['adShowing'] == true;
    final adInterrupting = payload['adInterrupting'] == true;
    if (adShowing || adInterrupting) {
      _logPiPEvent(
        'autoNext skip reason=ad_state adShowing=$adShowing adInterrupting=$adInterrupting',
      );
      return;
    }

    if (_isShortsUrlFromDebugPayload(payload)) {
      _logPiPEvent('autoNext skip reason=shorts_url');
      return;
    }

    final videoId = _videoIdFromDebugPayload(payload);
    final listId = _listIdFromDebugPayload(payload);
    final hasListContext = _hasListContextFromDebugPayload(payload);
    if (_isDuplicateEndedAutoNext(videoId: videoId, source: 'dart_ended')) {
      return;
    }
    _markEndedAutoNext(videoId: videoId, source: 'dart_ended');
    final now = DateTime.now();
    final lastTriggeredAt = _lastAutoNextTriggeredAt;
    if (videoId.isNotEmpty &&
        _lastAutoNextVideoId == videoId &&
        lastTriggeredAt != null &&
        now.difference(lastTriggeredAt) < _autoNextDuplicateWindow) {
      _logPiPEvent(
        'autoNext skip reason=duplicate videoId=$videoId windowMs=${_autoNextDuplicateWindow.inMilliseconds}',
      );
      return;
    }

    final token = ++_autoNextToken;
    _autoNextPending = true;
    _autoNextArmedVideoId = videoId.isEmpty ? null : videoId;
    _autoNextArmedListId = listId.isEmpty ? null : listId;
    _setAutoNextTransitioning(true, reason: 'armed');
    _logPiPEvent(
      'autoNext armed token=$token videoId=$videoId listId=$listId hasList=$hasListContext delayMs=${_autoNextDelay.inMilliseconds} hasNext=$_hasNext inPiP=$_isInPiPMode',
    );
    unawaited(
      _runAutoNextTimer(token: token, videoId: videoId, listId: listId),
    );
  }

  Future<void> _runAutoNextTimer({
    required int token,
    required String videoId,
    required String listId,
  }) async {
    await Future<void>.delayed(_autoNextDelay);
    if (!mounted || token != _autoNextToken) {
      return;
    }

    await _publishVideoStateNow(force: true);
    await Future<void>.delayed(_autoNextStateSettle);
    if (!mounted || token != _autoNextToken) {
      return;
    }

    final currentVideoIdBeforeAttempt = _currentKnownVideoId();
    if (videoId.isNotEmpty &&
        currentVideoIdBeforeAttempt.isNotEmpty &&
        currentVideoIdBeforeAttempt != videoId) {
      _autoNextPending = false;
      _autoNextArmedVideoId = null;
      _autoNextArmedListId = null;
      _setAutoNextTransitioning(false, reason: 'already_transitioned');
      _logPiPEvent(
        'autoNext skip reason=already_transitioned token=$token endedVideoId=$videoId currentVideoId=$currentVideoIdBeforeAttempt',
      );
      return;
    }
    if (_videoPlaying) {
      final isSameVideoReplay =
          videoId.isNotEmpty &&
          currentVideoIdBeforeAttempt.isNotEmpty &&
          currentVideoIdBeforeAttempt == videoId;
      if (!isSameVideoReplay) {
        _autoNextPending = false;
        _autoNextArmedVideoId = null;
        _autoNextArmedListId = null;
        _setAutoNextTransitioning(false, reason: 'already_playing_new_video');
        _logPiPEvent(
          'autoNext skip reason=already_playing_new_video token=$token endedVideoId=$videoId currentVideoId=$currentVideoIdBeforeAttempt',
        );
        return;
      }
      _logPiPEvent(
        'autoNext replay_detected token=$token endedVideoId=$videoId -> continue next attempt',
      );
    }

    final triggeredPrimary = await _attemptNextWithVerification(
      token: token,
      reason: 'auto_next_primary',
      endedVideoId: videoId,
      endedListId: listId,
    );
    if (!mounted || token != _autoNextToken) {
      return;
    }

    var triggered = triggeredPrimary;
    if (!triggered) {
      await Future<void>.delayed(_autoNextRetryDelay);
      if (!mounted || token != _autoNextToken) {
        return;
      }
      await _publishVideoStateNow(force: true);
      await Future<void>.delayed(_autoNextStateSettle);
      if (!mounted || token != _autoNextToken) {
        return;
      }
      triggered = await _attemptNextWithVerification(
        token: token,
        reason: 'auto_next_retry',
        endedVideoId: videoId,
        endedListId: listId,
      );
    }
    if (!mounted || token != _autoNextToken) {
      return;
    }

    _autoNextPending = false;
    _autoNextArmedVideoId = null;
    _autoNextArmedListId = null;
    if (!triggered) {
      _setAutoNextTransitioning(false, reason: 'trigger_failed');
      _logPiPEvent(
        'autoNext trigger_failed token=$token videoId=$videoId listId=$listId hasNext=$_hasNext',
      );
      return;
    }

    _lastAutoNextVideoId = videoId.isEmpty ? null : videoId;
    _lastAutoNextTriggeredAt = DateTime.now();
    _logPiPEvent(
      'autoNext triggered token=$token fromVideoId=$videoId toVideoId=${_currentKnownVideoId()} listId=$listId',
    );

    await Future<void>.delayed(_autoNextStateSettle);
    if (!mounted || token != _autoNextToken) {
      return;
    }
    await _publishVideoStateNow(force: true);
    _setAutoNextTransitioning(false, reason: 'triggered_confirmed');
  }

  Future<bool> _attemptNextWithVerification({
    required int token,
    required String reason,
    required String endedVideoId,
    required String endedListId,
  }) async {
    final actionIssued = await _nextVideoFromWebView(reason: reason);
    if (!mounted || token != _autoNextToken) {
      return false;
    }
    if (!actionIssued) {
      return false;
    }
    if (endedVideoId.isEmpty) {
      return true;
    }
    return _waitForVideoTransitionAfterNext(
      token: token,
      previousVideoId: endedVideoId,
      previousListId: endedListId,
    );
  }

  Future<bool> _waitForVideoTransitionAfterNext({
    required int token,
    required String previousVideoId,
    required String previousListId,
  }) async {
    const Duration timeout = Duration(milliseconds: 2200);
    const Duration step = Duration(milliseconds: 220);
    final startedAt = DateTime.now();
    while (DateTime.now().difference(startedAt) < timeout) {
      if (!mounted || token != _autoNextToken) {
        return false;
      }
      await Future<void>.delayed(step);
      if (!mounted || token != _autoNextToken) {
        return false;
      }
      await _publishVideoStateNow(force: true);
      await Future<void>.delayed(_autoNextStateSettle);
      if (!mounted || token != _autoNextToken) {
        return false;
      }
      final currentVideoId = _currentKnownVideoId();
      if (currentVideoId.isEmpty) {
        continue;
      }
      if (currentVideoId != previousVideoId) {
        final currentListId = _currentKnownListId();
        _setAutoNextTransitioning(false, reason: 'transition_confirmed');
        _logPiPEvent(
          'autoNext transition previousVideoId=$previousVideoId currentVideoId=$currentVideoId previousListId=$previousListId currentListId=$currentListId',
        );
        return true;
      }
    }
    _logPiPEvent(
      'autoNext transition_timeout previousVideoId=$previousVideoId currentVideoId=${_currentKnownVideoId()} previousListId=$previousListId currentListId=${_currentKnownListId()}',
    );
    _setAutoNextTransitioning(false, reason: 'transition_timeout');
    return false;
  }

  bool _shouldCancelAutoNextOnPlaying(Map<String, dynamic> payload) {
    if (!_autoNextPending) {
      return false;
    }
    final armedVideoId = (_autoNextArmedVideoId ?? '').trim();
    if (armedVideoId.isEmpty) {
      return false;
    }
    final playingVideoId = _videoIdFromDebugPayload(payload);
    if (playingVideoId.isEmpty) {
      return false;
    }
    return playingVideoId != armedVideoId;
  }

  bool _shouldCancelAutoNextOnVideoStatePlaying() {
    if (!_autoNextPending) {
      return false;
    }
    final armedVideoId = (_autoNextArmedVideoId ?? '').trim();
    if (armedVideoId.isEmpty) {
      return false;
    }
    final currentVideoId = _currentKnownVideoId();
    if (currentVideoId.isEmpty) {
      return false;
    }
    return currentVideoId != armedVideoId;
  }

  void _handlePlaybackDebugPayload(Map<String, dynamic> payload) {
    _logPlaybackDebugPayload(payload);
    _adblockService.onPlaybackDebugSignal(
      payload,
      pageUri: _currentMainFrameUri,
    );

    final eventName = (payload['event'] ?? '').toString().trim();
    final observedVideoId = _videoIdFromDebugPayload(payload);
    final observedListId = _listIdFromDebugPayload(payload);
    final observedUrl = (payload['url'] ?? '').toString().trim();
    if (observedVideoId.isNotEmpty) {
      _lastObservedVideoId = observedVideoId;
    }
    if (Uri.tryParse(observedUrl) != null) {
      _lastObservedListId = observedListId;
    }
    _syncMediaMetadataFromDebugPayload(payload);
    final pageVisibility = (payload['pageVisibility'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (eventName == 'doc:visibilitychange') {
      _logPiPEvent(
        'jsVisibility event=$eventName page=$pageVisibility inPiP=$_isInPiPMode inForeground=$_isAppInForeground playing=$_videoPlaying',
      );
    }
    if (eventName.startsWith('auto-next:bg-')) {
      final eventVideoId = observedVideoId.isNotEmpty
          ? observedVideoId
          : _currentKnownVideoId();
      _logPiPEvent(
        'bgAutoNext event=$eventName videoId=$eventVideoId inForeground=$_isAppInForeground guard=$_backgroundPlaybackGuardEnabled',
      );
      if (eventName.startsWith('auto-next:bg-triggered')) {
        _markEndedAutoNext(videoId: eventVideoId, source: 'js_bg_triggered');
        _cancelPendingAutoNext(reason: 'js_bg_triggered');
        _setAutoNextTransitioning(false, reason: 'js_bg_triggered');
        _schedulePostAutoNextTitleRefresh(reason: eventName);
      }
    }
    if (eventName == 'video:ended') {
      final endedVideoId = observedVideoId.isNotEmpty
          ? observedVideoId
          : _currentKnownVideoId();
      if (!_isAppInForeground) {
        _logPiPEvent(
          'ended_received_bg videoId=$endedVideoId bg_guard_active=$_backgroundPlaybackGuardEnabled',
        );
      } else {
        _logPiPEvent('ended_received_fg videoId=$endedVideoId');
      }
      _scheduleAutoNextFromEnded(payload);
    } else if (eventName == 'yt:navigate-start' ||
        eventName == 'video:loadstart') {
      _cancelPendingAutoNext(reason: 'event_$eventName');
    } else if (eventName == 'video:playing') {
      if (_shouldCancelAutoNextOnPlaying(payload)) {
        _cancelPendingAutoNext(reason: 'event_$eventName');
      }
    }

    if (eventName != 'ui:ytp-play-button:click') {
      return;
    }

    _logPiPEvent(
      'ytPlayPauseClick page=$pageVisibility inPiP=$_isInPiPMode localPlaying=$_videoPlaying',
    );
    if (_isInPiPMode || pageVisibility != 'visible') {
      return;
    }

    final wasPlaying = _videoPlaying;
    final expectedPlaying = !wasPlaying;
    final token = ++_youtubePlayPauseClickToken;
    unawaited(
      _runYouTubePlayPauseFallback(
        token: token,
        wasPlaying: wasPlaying,
        expectedPlaying: expectedPlaying,
      ),
    );
  }

  Future<void> _runYouTubePlayPauseFallback({
    required int token,
    required bool wasPlaying,
    required bool expectedPlaying,
  }) async {
    await Future<void>.delayed(_youtubeClickFallbackDelay);
    if (!mounted || _isInPiPMode || token != _youtubePlayPauseClickToken) {
      return;
    }

    await _publishVideoStateNow(force: true);
    await Future<void>.delayed(_youtubeClickFallbackSettle);
    if (!mounted || _isInPiPMode || token != _youtubePlayPauseClickToken) {
      return;
    }

    if (_videoPlaying == expectedPlaying || _videoPlaying != wasPlaying) {
      _logPiPEvent(
        'ytPlayPauseClick accepted token=$token before=$wasPlaying now=$_videoPlaying expected=$expectedPlaying',
      );
      return;
    }

    final action = expectedPlaying ? 'play' : 'pause';
    if (expectedPlaying) {
      await _forcePlayVideoInWebView();
    } else {
      await _pauseVideoInWebView();
    }

    await Future<void>.delayed(_youtubeClickFallbackSettle);
    if (!mounted || token != _youtubePlayPauseClickToken) {
      return;
    }
    await _publishVideoStateNow(force: true);
    _logPiPEvent(
      'ytPlayPauseFallback forced=$action token=$token final=$_videoPlaying',
    );
  }

  void _updateVideoState({
    required bool isPlaying,
    required bool isFullscreen,
    required int videoWidth,
    required int videoHeight,
    required int videoRectLeft,
    required int videoRectTop,
    required int videoRectRight,
    required int videoRectBottom,
    required String title,
    required String author,
    required int durationMs,
    required int positionMs,
    required bool hasNext,
    String videoId = '',
  }) {
    final normalizedVideoId = videoId.trim();
    final knownVideoId = normalizedVideoId.isNotEmpty
        ? normalizedVideoId
        : _currentKnownVideoId().trim();
    final resolvedTitle = _resolvedVideoTitle(
      title: title,
      videoId: knownVideoId,
      fallbackTitle: _mediaTitle,
    );
    final previousBoundVideoId = _titleBoundVideoId.trim();
    final videoChanged =
        knownVideoId.isNotEmpty &&
        previousBoundVideoId.isNotEmpty &&
        knownVideoId != previousBoundVideoId;
    var resolvedAuthor = author.trim();
    if (resolvedAuthor.isEmpty && !videoChanged) {
      resolvedAuthor = _mediaAuthor;
    }
    if (resolvedTitle.isEmpty && videoChanged) {
      resolvedAuthor = '';
    }
    final nextTitleBoundVideoId = resolvedTitle.isNotEmpty
        ? (knownVideoId.isNotEmpty ? knownVideoId : previousBoundVideoId)
        : '';
    final hasChanges =
        _videoPlaying != isPlaying ||
        _videoFullscreen != isFullscreen ||
        _videoWidth != videoWidth ||
        _videoHeight != videoHeight ||
        _videoRectLeft != videoRectLeft ||
        _videoRectTop != videoRectTop ||
        _videoRectRight != videoRectRight ||
        _videoRectBottom != videoRectBottom ||
        _mediaTitle != resolvedTitle ||
        _mediaAuthor != resolvedAuthor ||
        _durationMs != durationMs ||
        _positionMs != positionMs ||
        _hasNext != hasNext ||
        _titleBoundVideoId != nextTitleBoundVideoId;
    if (!hasChanges) {
      return;
    }
    setState(() {
      _videoPlaying = isPlaying;
      _videoFullscreen = isFullscreen;
      _videoWidth = videoWidth;
      _videoHeight = videoHeight;
      _videoRectLeft = videoRectLeft;
      _videoRectTop = videoRectTop;
      _videoRectRight = videoRectRight;
      _videoRectBottom = videoRectBottom;
      _mediaTitle = resolvedTitle;
      _mediaAuthor = resolvedAuthor;
      _durationMs = durationMs;
      _positionMs = positionMs;
      _hasNext = hasNext;
      _titleBoundVideoId = nextTitleBoundVideoId;
    });
    _pipState = PiPVideoState(
      isPlaying: isPlaying,
      isFullscreen: isFullscreen,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      videoRectLeft: videoRectLeft,
      videoRectTop: videoRectTop,
      videoRectRight: videoRectRight,
      videoRectBottom: videoRectBottom,
      title: resolvedTitle,
      author: resolvedAuthor,
      durationMs: durationMs,
      positionMs: positionMs,
      hasNext: hasNext,
    );
    unawaited(_pipController.updateState(_pipState));

    if (_isInPiPMode && !isPlaying) {
      if (!_pauseRequestedByUserInPiP) {
        unawaited(_attemptPiPRecoveryIfNeeded());
      }
    } else if (isPlaying) {
      _pauseRequestedByUserInPiP = false;
      if (_shouldCancelAutoNextOnVideoStatePlaying()) {
        _cancelPendingAutoNext(reason: 'video_state_playing');
      }
    }
    unawaited(_syncBackgroundPlaybackGuard(reason: 'video_state_changed'));
  }

  Future<void> _injectVideoStateScript({bool force = false}) async {
    final controller = _webViewController;
    if (controller == null) {
      return;
    }
    if (_isInjectingVideoStateScript) {
      return;
    }
    final now = DateTime.now();
    final lastInjectedAt = _lastVideoStateScriptInjectAt;
    if (!force &&
        lastInjectedAt != null &&
        now.difference(lastInjectedAt) < _scriptResyncThrottle) {
      return;
    }
    _isInjectingVideoStateScript = true;
    try {
      await controller.evaluateJavascript(source: goPlayVideoStateScript);
      await controller.evaluateJavascript(source: goPlayPlaybackDebugScript);
    } catch (_) {
    } finally {
      _lastVideoStateScriptInjectAt = DateTime.now();
      _isInjectingVideoStateScript = false;
    }
  }

  Future<void> _setBackgroundPlaybackGuardEnabled(
    bool enabled, {
    required String reason,
  }) async {
    final controller = _webViewController;
    if (controller == null) {
      _backgroundPlaybackGuardEnabled = false;
      return;
    }
    if (_backgroundPlaybackGuardEnabled == enabled) {
      return;
    }

    final script = enabled
        ? goPlayEnableBackgroundPlaybackScript
        : goPlayDisableBackgroundPlaybackScript;
    try {
      final rawResult = await controller.evaluateJavascript(source: script);
      final result = _asStringDynamicMap(rawResult);
      _backgroundPlaybackGuardEnabled = enabled;
      _logPiPEvent(
        'backgroundGuard enabled=$enabled reason=$reason result=$result',
      );
    } catch (_) {}
  }

  Future<void> _syncBackgroundPlaybackGuard({required String reason}) async {
    final shouldEnable =
        _settingsController.backgroundPlaybackEnabled &&
        !_isAppInForeground &&
        !_isInPiPMode;
    _logPiPEvent(
      'backgroundGuard sync reason=$reason shouldEnable=$shouldEnable inForeground=$_isAppInForeground inPiP=$_isInPiPMode playing=$_videoPlaying pipPlaying=${_pipState.isPlaying}',
    );
    await _setBackgroundPlaybackGuardEnabled(shouldEnable, reason: reason);
  }

  Future<void> _publishVideoStateNow({
    bool force = false,
    String reason = 'unspecified',
  }) async {
    final controller = _webViewController;
    if (controller == null) {
      _logPiPEvent('publishState skip reason=$reason cause=no_controller');
      return;
    }
    if (_isPublishingVideoState) {
      _logPiPEvent('publishState skip reason=$reason cause=busy');
      return;
    }
    final now = DateTime.now();
    final lastPublishedAt = _lastPublishVideoStateAt;
    if (!force &&
        lastPublishedAt != null &&
        now.difference(lastPublishedAt) < _videoStatePublishThrottle) {
      final elapsedMs = now.difference(lastPublishedAt).inMilliseconds;
      _logPiPEvent(
        'publishState skip reason=$reason cause=throttle elapsedMs=$elapsedMs',
      );
      return;
    }
    final startedAt = DateTime.now();
    _logPiPEvent('publishState start reason=$reason force=$force');
    _isPublishingVideoState = true;
    try {
      await controller.evaluateJavascript(
        source: goPlayPublishVideoStateScript,
      );
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      _logPiPEvent('publishState done reason=$reason elapsedMs=$elapsedMs');
    } catch (error) {
      _logPiPEvent('publishState error reason=$reason error=$error');
      rethrow;
    } finally {
      _lastPublishVideoStateAt = DateTime.now();
      _isPublishingVideoState = false;
    }
  }

  Future<void> _publishVideoStateWithRetry({
    int attempts = 2,
    Duration interval = const Duration(milliseconds: 120),
    String reason = 'retry',
  }) async {
    for (var i = 0; i < attempts; i += 1) {
      await _publishVideoStateNow(
        force: true,
        reason: '$reason#${i + 1}/$attempts',
      );
      if (i + 1 < attempts) {
        await Future<void>.delayed(interval);
      }
    }
  }

  Future<bool> _prepareWebViewForPiP() async {
    final controller = _webViewController;
    if (controller == null) {
      return false;
    }
    final result = await controller.evaluateJavascript(
      source: goPlayPreparePiPVideoOnlyScript,
    );
    return _asBool(result);
  }

  Future<void> _restoreWebViewAfterPiP({
    bool aggressive = false,
    String reason = 'generic',
  }) async {
    final controller = _webViewController;
    if (controller == null) {
      return;
    }
    final attempts = aggressive ? 3 : 1;
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      try {
        final rawResult = await controller.evaluateJavascript(
          source: goPlayRestorePiPVideoOnlyScript,
        );
        final result = _asStringDynamicMap(rawResult);
        _logPiPEvent(
          'restore reason=$reason attempt=${attempt + 1}/$attempts aggressive=$aggressive result=$result',
        );
      } catch (_) {}
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  Future<bool> _restoreForPiPExitIfNeeded({required String reason}) async {
    if (_isInPiPMode) {
      _logPiPEvent('restoreForPiPExit skip reason=$reason cause=still_in_pip');
      return false;
    }
    if (!_awaitingPiPExitRestore || _pipExitRestoreHandled) {
      _logPiPEvent(
        'restoreForPiPExit skip reason=$reason awaiting=$_awaitingPiPExitRestore handled=$_pipExitRestoreHandled',
      );
      return false;
    }
    _logPiPEvent('restoreForPiPExit start reason=$reason');
    await _restoreWebViewAfterPiP(aggressive: false, reason: reason);
    _pipExitRestoreHandled = true;
    _awaitingPiPExitRestore = false;
    if (mounted && _isPreparingPiPLayout) {
      setState(() {
        _isPreparingPiPLayout = false;
      });
    }
    await _runPiPExitCompactGuard(reason: reason);
    _logPiPEvent('restoreForPiPExit done reason=$reason');
    return true;
  }

  Future<Map<String, dynamic>> _readVideoLayoutStateFromWebView() async {
    final controller = _webViewController;
    if (controller == null) {
      return const <String, dynamic>{};
    }
    try {
      final rawState = await controller.evaluateJavascript(
        source: goPlayReadVideoLayoutStateScript,
      );
      return _asStringDynamicMap(rawState);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  bool _isCompactVideoLayout(Map<String, dynamic> state) {
    if (state.isEmpty) {
      return false;
    }
    if (state['compact'] == true) {
      return true;
    }
    final viewportWidth = _toPositiveDouble(state['viewportWidth']);
    final videoCssWidth = _toPositiveDouble(state['videoCssWidth']);
    if (viewportWidth <= 0 || videoCssWidth <= 0) {
      return false;
    }
    final ratio = videoCssWidth / viewportWidth;
    return ratio < _pipCompactWidthRatioThreshold;
  }

  Future<Map<String, dynamic>> _runPostRestoreNormalizationSequence({
    required String reason,
  }) async {
    final controller = _webViewController;
    if (controller == null) {
      return const <String, dynamic>{};
    }
    try {
      final rawResult = await controller.evaluateJavascript(
        source: goPlayNormalizeAfterPiPExitScript,
      );
      final result = _asStringDynamicMap(rawResult);
      final beforeCompact = result['beforeCompact'] == true;
      final afterCompact = result['afterCompact'] == true;
      final hasMiniAfter = result['hasMiniAfter'] == true;
      final viewportWidth = _toPositiveDouble(result['viewportWidth']);
      final afterCssWidth = _toPositiveDouble(result['afterCssWidth']);
      final ratioLabel = viewportWidth > 0
          ? (afterCssWidth / viewportWidth).toStringAsFixed(3)
          : 'n/a';
      final expandClicked = result['expandClicked'] == true;
      final expandSelector = (result['expandSelector'] ?? '').toString();
      _logPiPEvent(
        'normalize reason=$reason beforeCompact=$beforeCompact afterCompact=$afterCompact miniAfter=$hasMiniAfter ratio=$ratioLabel css=${afterCssWidth.round()} viewport=${viewportWidth.round()} expandClicked=$expandClicked expandSelector=$expandSelector',
      );
      return result;
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<bool> _softReloadWatchPageAfterPiPExit({
    required String reason,
  }) async {
    final controller = _webViewController;
    if (controller == null) {
      return false;
    }
    final currentUri = _currentMainFrameUri;
    final host = currentUri.host.toLowerCase();
    final isYouTubeHost =
        host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host.endsWith('.youtube.com');
    if (!isYouTubeHost) {
      return false;
    }
    if (!currentUri.path.toLowerCase().contains('/watch')) {
      return false;
    }
    final videoId = (currentUri.queryParameters['v'] ?? '').trim();
    if (videoId.isEmpty) {
      return false;
    }

    final queryParameters = Map<String, String>.from(
      currentUri.queryParameters,
    );
    queryParameters.remove('t');
    final resumePositionMs = _positionMs > 0
        ? _positionMs
        : _pipState.positionMs;
    final knownVideoId = _currentKnownVideoId().trim();
    final shouldApplyResumePosition =
        (_videoPlaying || _pipState.isPlaying) &&
        (knownVideoId.isEmpty || knownVideoId == videoId) &&
        resumePositionMs >= _pipExitFallbackMinResumePosition.inMilliseconds;
    if (shouldApplyResumePosition) {
      final resumeSeconds = (resumePositionMs / 1000).floor();
      if (resumeSeconds > 0) {
        queryParameters['t'] = '${resumeSeconds}s';
      }
    }
    final reloadUri = currentUri.replace(queryParameters: queryParameters);
    final resumeLabel = queryParameters['t'] ?? '';
    _logPiPEvent(
      'exitCompactFallback reason=$reason uri=${reloadUri.host}${reloadUri.path}?v=$videoId&t=$resumeLabel',
    );
    try {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(reloadUri.toString())),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _runPiPExitCompactGuard({required String reason}) async {
    if (_isInPiPMode) {
      return;
    }
    final token = ++_pipExitNormalizationToken;
    var stillCompactAfterNormalize = false;
    for (var index = 0; index < _pipExitCompactCheckDelays.length; index += 1) {
      final delay = _pipExitCompactCheckDelays[index];
      await Future<void>.delayed(delay);
      if (!mounted || _isInPiPMode || token != _pipExitNormalizationToken) {
        return;
      }

      final layoutState = await _readVideoLayoutStateFromWebView();
      if (!mounted || _isInPiPMode || token != _pipExitNormalizationToken) {
        return;
      }
      final hasMiniPlayer = layoutState['hasMiniPlayer'] == true;
      final pageVisibility = (layoutState['pageVisibility'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (pageVisibility != 'visible') {
        _logPiPEvent(
          'compactCheck reason=$reason step=${index + 1}/${_pipExitCompactCheckDelays.length} skipped page=$pageVisibility',
        );
        stillCompactAfterNormalize = false;
        continue;
      }
      final compactBeforeNormalize =
          _isCompactVideoLayout(layoutState) || hasMiniPlayer;
      final viewportWidth = _toPositiveDouble(layoutState['viewportWidth']);
      final videoCssWidth = _toPositiveDouble(layoutState['videoCssWidth']);
      final ratioLabel = viewportWidth > 0
          ? (videoCssWidth / viewportWidth).toStringAsFixed(3)
          : 'n/a';
      _logPiPEvent(
        'compactCheck reason=$reason step=${index + 1}/${_pipExitCompactCheckDelays.length} compact=$compactBeforeNormalize mini=$hasMiniPlayer ratio=$ratioLabel css=${videoCssWidth.round()} viewport=${viewportWidth.round()}',
      );

      if (!compactBeforeNormalize) {
        stillCompactAfterNormalize = false;
        break;
      }

      final normalizationResult = await _runPostRestoreNormalizationSequence(
        reason: '$reason:step${index + 1}',
      );
      if (!mounted || _isInPiPMode || token != _pipExitNormalizationToken) {
        return;
      }
      final compactAfterNormalize = normalizationResult['afterCompact'] == true;
      final hasMiniAfter = normalizationResult['hasMiniAfter'] == true;
      stillCompactAfterNormalize = compactAfterNormalize || hasMiniAfter;
      if (!stillCompactAfterNormalize) {
        break;
      }
    }

    if (!mounted || _isInPiPMode || token != _pipExitNormalizationToken) {
      return;
    }
    if (!stillCompactAfterNormalize) {
      return;
    }
    final reloaded = await _softReloadWatchPageAfterPiPExit(reason: reason);
    _logPiPEvent('compactFallbackReload reason=$reason reloaded=$reloaded');
  }

  bool _isPiPLayoutStale(Map<String, dynamic> state) {
    if (state.isEmpty) {
      return false;
    }
    final pathCount = _toInt(state['pathCount']);
    final videoCount = _toInt(state['videoCount']);
    return state['pipActive'] == true ||
        state['hasActiveClass'] == true ||
        state['hasStyle'] == true ||
        pathCount > 0 ||
        videoCount > 0;
  }

  Future<void> _checkAndRepairStalePiPLayout({
    required String reason,
    bool force = false,
  }) async {
    if (_isInPiPMode || _pipLayoutRepairInProgress) {
      return;
    }

    final now = DateTime.now();
    final lastCheckedAt = _lastPiPLayoutHealthCheckAt;
    if (!force &&
        lastCheckedAt != null &&
        now.difference(lastCheckedAt) < _pipLayoutHealthThrottle) {
      return;
    }
    _lastPiPLayoutHealthCheckAt = now;

    final controller = _webViewController;
    if (controller == null) {
      return;
    }

    Map<String, dynamic> state;
    try {
      final rawState = await controller.evaluateJavascript(
        source: goPlayReadPiPLayoutStateScript,
      );
      state = _asStringDynamicMap(rawState);
    } catch (_) {
      return;
    }

    final stale = _isPiPLayoutStale(state);
    if (!stale) {
      if (force) {
        _logPiPEvent('layout healthy reason=$reason state=$state');
      }
      return;
    }

    _pipLayoutRepairInProgress = true;
    try {
      _logPiPEvent('layout stale reason=$reason state=$state -> repairing');
      await _restoreWebViewAfterPiP(
        aggressive: true,
        reason: '$reason:stale_layout',
      );
      await _publishVideoStateNow(force: true);
    } finally {
      _pipLayoutRepairInProgress = false;
    }
  }

  Future<void> _handleAppResumedLifecycle() async {
    try {
      final nativeInPiP = await _pipController.refreshPiPModeFromNative();
      _logPiPEvent(
        'resume localInPiP=$_isInPiPMode nativeInPiP=$nativeInPiP preparing=$_isPreparingPiPLayout',
      );
      if (mounted &&
          (_isInPiPMode != nativeInPiP ||
              (_isPreparingPiPLayout && !nativeInPiP))) {
        setState(() {
          _isInPiPMode = nativeInPiP;
          if (!nativeInPiP) {
            _isPreparingPiPLayout = false;
          }
        });
      }
      if (nativeInPiP) {
        return;
      }
      _pauseRequestedByUserInPiP = false;
      _resetPiPRecoveryState();
      final restored = await _restoreForPiPExitIfNeeded(
        reason: 'app_resumed_exit_fallback',
      );
      if (!restored) {
        await _checkAndRepairStalePiPLayout(reason: 'app_resumed', force: true);
        await _runPiPExitCompactGuard(reason: 'app_resumed_no_restore');
      }
      await _publishVideoStateNow(
        force: true,
        reason: 'app_resumed_final_sync',
      );
    } catch (_) {
      if (!_isInPiPMode) {
        _pauseRequestedByUserInPiP = false;
        _resetPiPRecoveryState();
        await _restoreForPiPExitIfNeeded(reason: 'app_resumed_error_fallback');
        await _publishVideoStateNow(
          force: true,
          reason: 'app_resumed_error_sync',
        );
      }
    }
  }

  bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  Future<bool> _togglePlayPauseFromWebView() async {
    final controller = _webViewController;
    if (controller == null) {
      return false;
    }
    final result = await controller.evaluateJavascript(
      source: goPlayTogglePlayPauseScript,
    );
    return _asBool(result);
  }

  Future<bool> _forcePlayVideoInWebView() async {
    final controller = _webViewController;
    if (controller == null) {
      return false;
    }
    final result = await controller.evaluateJavascript(
      source: goPlayForcePlayVideoScript,
    );
    return _asBool(result);
  }

  Future<void> _ensurePlaybackAfterPiPEntry() async {
    // Keep this lightweight to avoid repeated audio-focus churn.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await _publishVideoStateNow(force: true);
  }

  void _resetPiPRecoveryState() {
    _pipRecoveryInProgress = false;
    _pipRecoveryBudget = 0;
    _pipTransitionDeadline = null;
    _pipPlayCommandCount = 0;
  }

  Future<void> _attemptPiPRecoveryIfNeeded() async {
    if (!_isInPiPMode) {
      return;
    }
    if (_videoPlaying) {
      return;
    }
    if (_pipRecoveryInProgress) {
      return;
    }
    if (_pipRecoveryBudget <= 0) {
      return;
    }
    if (!_isInsidePiPTransitionWindow()) {
      return;
    }
    _pipRecoveryInProgress = true;
    try {
      _pipRecoveryBudget -= 1;
      await _sendPlayCommandToWebView();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _publishVideoStateNow(force: true);
    } finally {
      _pipRecoveryInProgress = false;
    }
  }

  bool _isInsidePiPTransitionWindow() {
    final deadline = _pipTransitionDeadline;
    if (deadline == null) {
      return false;
    }
    return DateTime.now().isBefore(deadline);
  }

  Future<void> _sendPlayCommandToWebView() async {
    _pipPlayCommandCount += 1;
    _logPiPEvent(
      'playAttempt=$_pipPlayCommandCount remaining=$_pipRecoveryBudget inWindow=${_isInsidePiPTransitionWindow()}',
    );
    await _forcePlayVideoInWebView();
  }

  void _armPiPRecoveryBudget() {
    if (!_isInPiPMode) {
      return;
    }
    _pipRecoveryInProgress = false;
    _pauseRequestedByUserInPiP = false;
    _pipTransitionDeadline = DateTime.now().add(_pipTransitionWindow);
    _pipRecoveryBudget = _maxPiPRecoveryAttempts;
    _pipPlayCommandCount = 0;
  }

  Future<bool> _pauseVideoInWebView() async {
    final controller = _webViewController;
    if (controller == null) {
      return false;
    }
    final result = await controller.evaluateJavascript(
      source: goPlayPauseVideoScript,
    );
    return _asBool(result);
  }

  Future<bool> _nextVideoFromWebView({required String reason}) async {
    final controller = _webViewController;
    if (controller == null) {
      return false;
    }
    final rawResult = await controller.evaluateJavascript(
      source: goPlayNextVideoScript,
    );
    final parsedResult = _asStringDynamicMap(rawResult);
    if (parsedResult.isNotEmpty) {
      final ok = _asBool(parsedResult['ok']);
      final strategy = (parsedResult['strategy'] ?? '').toString().trim();
      final listId = (parsedResult['listId'] ?? '').toString().trim();
      final currentVideoId = (parsedResult['currentVideoId'] ?? '')
          .toString()
          .trim();
      final nextUrl = (parsedResult['nextUrl'] ?? '').toString().trim();
      _logPiPEvent(
        'nextVideo reason=$reason ok=$ok strategy=$strategy listId=$listId videoId=$currentVideoId nextUrl=$nextUrl',
      );
      return ok;
    }

    final ok = _asBool(rawResult);
    _logPiPEvent('nextVideo reason=$reason ok=$ok strategy=legacy_bool');
    return ok;
  }

  Future<int> _readBufferedAheadMsFromWebView() async {
    final controller = _webViewController;
    if (controller == null) {
      return 0;
    }
    try {
      final result = await controller.evaluateJavascript(
        source: goPlayReadBufferedAheadMsScript,
      );
      return _toPositiveInt(result);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _warmBufferBeforePiPEntry() async {
    if (!_videoPlaying) {
      return;
    }
    const int targetBufferAheadMs = 6000;
    const Duration maxWait = Duration(milliseconds: 1800);
    const Duration step = Duration(milliseconds: 220);
    final startedAt = DateTime.now();
    while (DateTime.now().difference(startedAt) < maxWait) {
      final bufferAheadMs = await _readBufferedAheadMsFromWebView();
      if (bufferAheadMs >= targetBufferAheadMs) {
        return;
      }
      await Future<void>.delayed(step);
    }
  }

  Future<void> _requestPiPFromBrowser() async {
    if (_isRequestingPiP) {
      return;
    }
    _isRequestingPiP = true;
    try {
      if (!_videoPlaying) {
        await _publishVideoStateNow(force: true);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      if (!_videoPlaying) {
        return;
      }
      await _warmBufferBeforePiPEntry();
      if (mounted && !_isPreparingPiPLayout) {
        setState(() {
          _isPreparingPiPLayout = true;
        });
      }
      final prepared = await _prepareWebViewForPiP();
      if (!prepared) {
        if (mounted) {
          setState(() {
            _isPreparingPiPLayout = false;
          });
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await _publishVideoStateNow(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final entered = await _pipController.enterPiPWithState(
        _pipState.copyWith(isPlaying: true, isFullscreen: true),
      );
      if (!entered) {
        await _restoreWebViewAfterPiP(aggressive: true, reason: 'enter_failed');
        if (mounted) {
          setState(() {
            _isPreparingPiPLayout = false;
          });
        }
      }
    } finally {
      _isRequestingPiP = false;
    }
  }

  Future<void> _onEnterPiPPressed() async {
    if (!_ensurePackageEnabled()) {
      return;
    }
    if (!_settingsController.pipEnabled) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('PiP is disabled in settings')),
        );
      return;
    }

    if (!_videoPlaying) {
      await _publishVideoStateNow(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (!_videoPlaying) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Play a video first to enter PiP')),
        );
      return;
    }

    await _requestPiPFromBrowser();
  }

  Future<dynamic> _onNativePiPEvent(MethodCall call) async {
    switch (call.method) {
      case 'onPiPAction':
        if (!_packageStatus.hasPackage) {
          await _pauseVideoInWebView();
          return null;
        }
        final rawArgs = call.arguments;
        final args = rawArgs is Map
            ? Map<String, dynamic>.from(rawArgs)
            : const <String, dynamic>{};
        final action = args['action']?.toString() ?? '';
        _logPiPEvent(
          'action received action=$action inPiP=$_isInPiPMode localPlaying=$_videoPlaying',
        );
        if (action.isNotEmpty) {
          _cancelPendingAutoNext(reason: 'pip_action_$action');
        }
        bool? expectedPlayingAfterAction;
        if (action == 'togglePlayPause') {
          final wasPlaying = _videoPlaying;
          expectedPlayingAfterAction = !wasPlaying;
          final toggled = await _togglePlayPauseFromWebView();
          _logPiPEvent(
            'toggle requested wasPlaying=$wasPlaying toggledByScript=$toggled',
          );
          if (!toggled) {
            if (wasPlaying) {
              _pauseRequestedByUserInPiP = true;
              await _pauseVideoInWebView();
            } else {
              _pauseRequestedByUserInPiP = false;
              await _sendPlayCommandToWebView();
            }
          } else {
            _pauseRequestedByUserInPiP = wasPlaying;
          }
        } else if (action == 'play') {
          expectedPlayingAfterAction = true;
          _pauseRequestedByUserInPiP = false;
          await _sendPlayCommandToWebView();
        } else if (action == 'pause') {
          expectedPlayingAfterAction = false;
          _pauseRequestedByUserInPiP = true;
          await _pauseVideoInWebView();
        } else if (action == 'next') {
          // Keep aggressive post-next play recovery only in PiP.
          // In foreground mode, forcing an extra play command can collide with
          // decoder re-initialization and increase black-screen latency.
          expectedPlayingAfterAction = _isInPiPMode ? true : null;
          _pauseRequestedByUserInPiP = false;
          await _nextVideoFromWebView(reason: 'pip_next_action');
          if (_isInPiPMode) {
            await Future<void>.delayed(const Duration(milliseconds: 70));
            await _sendPlayCommandToWebView();
          } else {
            _logPiPEvent('next action skip_force_play reason=not_in_pip');
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await _publishVideoStateWithRetry(reason: 'pip_action_$action');
        if (expectedPlayingAfterAction != null &&
            _videoPlaying != expectedPlayingAfterAction) {
          _logPiPEvent(
            'action verify mismatch action=$action expected=$expectedPlayingAfterAction actual=$_videoPlaying -> retry',
          );
          if (expectedPlayingAfterAction) {
            _pauseRequestedByUserInPiP = false;
            await _sendPlayCommandToWebView();
          } else {
            _pauseRequestedByUserInPiP = true;
            await _pauseVideoInWebView();
          }
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await _publishVideoStateWithRetry(
            reason: 'pip_action_${action}_verify_retry',
          );
        }
        _logPiPEvent(
          'action handled action=$action pauseRequested=$_pauseRequestedByUserInPiP localPlaying=$_videoPlaying',
        );
        return null;
      case 'onPiPModeChanged':
        final rawArgs = call.arguments;
        final args = rawArgs is Map
            ? Map<String, dynamic>.from(rawArgs)
            : const <String, dynamic>{};
        final isInPiPMode = args['isInPiPMode'] == true;
        _youtubePlayPauseClickToken += 1;
        _pipExitNormalizationToken += 1;
        _logPiPEvent('mode changed isInPiPMode=$isInPiPMode');
        _pipController.setPiPMode(isInPiPMode);
        if (mounted) {
          setState(() {
            _isInPiPMode = isInPiPMode;
            _isPreparingPiPLayout = false;
          });
        }
        if (isInPiPMode) {
          _awaitingPiPExitRestore = true;
          _pipExitRestoreHandled = false;
          _pauseRequestedByUserInPiP = false;
          _armPiPRecoveryBudget();
          await _ensurePlaybackAfterPiPEntry();
          await _attemptPiPRecoveryIfNeeded();
        } else {
          _pauseRequestedByUserInPiP = false;
          _resetPiPRecoveryState();
          final restored = await _restoreForPiPExitIfNeeded(
            reason: 'mode_changed_exit',
          );
          if (!restored) {
            await _checkAndRepairStalePiPLayout(
              reason: 'native_mode_changed_exit',
            );
            await _runPiPExitCompactGuard(
              reason: 'native_mode_changed_exit_no_restore',
            );
          }
        }
        await _syncBackgroundPlaybackGuard(reason: 'pip_mode_changed');
        await _publishVideoStateNow(
          force: true,
          reason: isInPiPMode
              ? 'pip_mode_changed_enter_sync'
              : 'pip_mode_changed_exit_sync',
        );
        return null;
      default:
        return null;
    }
  }

  Future<void> _syncAdblockScript({bool force = false}) async {
    final controller = _webViewController;
    if (controller == null) {
      _logAdblockTrace('syncScript skip reason=no_controller force=$force');
      return;
    }
    final now = DateTime.now();
    final lastSyncedAt = _lastAdblockScriptSyncAt;
    if (!force &&
        lastSyncedAt != null &&
        now.difference(lastSyncedAt) < _scriptResyncThrottle) {
      return;
    }
    _logAdblockTrace(
      'syncScript start force=$force enabled=${_settingsController.adblockEnabled}',
    );
    try {
      await controller.evaluateJavascript(source: goPlayPreferNonAv1Script);
      await controller.evaluateJavascript(
        source: _settingsController.adblockEnabled
            ? goPlayEnableAdblockScript
            : goPlayDisableAdblockScript,
      );
      await _adblockService.syncRuntimeLayers(force: force);
      _logAdblockTrace(
        'syncScript done force=$force enabled=${_settingsController.adblockEnabled}',
      );
    } catch (error) {
      _logAdblockTrace(
        'syncScript error force=$force enabled=${_settingsController.adblockEnabled} error=$error',
      );
    } finally {
      _lastAdblockScriptSyncAt = DateTime.now();
    }
  }

  Future<void> _prepareAdblockRuntime(InAppWebViewController controller) async {
    _logAdblockTrace('runtimeSetup start');
    try {
      await _adblockService.attachWebView(controller);
      _adblockService.onMainFrameChanged(_currentMainFrameUri);
      await _syncAdblockScript(force: true);
      if (!mounted || !identical(_webViewController, controller)) {
        return;
      }
      setState(() {
        _adblockRuntimeReady = true;
      });
      _logAdblockTrace('runtimeSetup done');
    } catch (error) {
      // Fail-open UI to avoid trapping users on a permanent loading overlay.
      _logAdblockTrace('runtimeSetup error=$error');
      if (!mounted || !identical(_webViewController, controller)) {
        return;
      }
      setState(() {
        _adblockRuntimeReady = true;
      });
    }
  }

  UnmodifiableListView<UserScript> _buildInitialUserScripts() {
    final adblockSource = _settingsController.adblockEnabled
        ? goPlayEnableAdblockScript
        : goPlayDisableAdblockScript;
    return UnmodifiableListView<UserScript>(<UserScript>[
      UserScript(
        groupName: 'go_play-codec-preference',
        source: goPlayPreferNonAv1Script,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: true,
      ),
      UserScript(
        groupName: 'go_play-adblock',
        source: adblockSource,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: true,
      ),
      UserScript(
        groupName: 'go_play-video-state',
        source: goPlayVideoStateScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        forMainFrameOnly: true,
      ),
      UserScript(
        groupName: 'go_play-playback-debug',
        source: goPlayPlaybackDebugScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        forMainFrameOnly: true,
      ),
    ]);
  }

  Future<void> _goBack() async {
    if (!_ensurePackageEnabled()) {
      return;
    }
    final controller = _webViewController;
    if (controller == null) {
      return;
    }
    if (await controller.canGoBack()) {
      await controller.goBack();
      await _updateCanGoBack();
    }
  }

  Future<void> _reload() async {
    if (!_ensurePackageEnabled()) {
      return;
    }
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
    final controller = _webViewController;
    if (controller == null) {
      return;
    }
    _markMainFrameNavigation(
      _toUri(await controller.getUrl()),
      resetRetryBudget: true,
    );
    await controller.reload();
  }

  Future<void> _retry() async {
    if (!_ensurePackageEnabled()) {
      return;
    }
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final controller = _webViewController;
    if (controller == null) {
      return;
    }
    _markMainFrameNavigation(AppConfig.homeUri, resetRetryBudget: true);
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(AppConfig.homeUri.toString())),
    );
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).pushNamed(AppRoutes.account);
  }

  Future<bool> _onWillPop() async {
    final controller = _webViewController;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      await _updateCanGoBack();
      return false;
    }
    return true;
  }

  String _blockedResponseCorsOrigin(Map<String, String>? requestHeaders) {
    final headers = requestHeaders ?? const <String, String>{};
    String? origin;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'origin') {
        origin = entry.value;
        break;
      }
    }
    if (origin == null || origin.trim().isEmpty) {
      for (final entry in headers.entries) {
        final key = entry.key.toLowerCase();
        if (key == 'referer' || key == 'referrer') {
          final refererUri = Uri.tryParse(entry.value);
          if (refererUri != null &&
              refererUri.scheme.isNotEmpty &&
              refererUri.host.isNotEmpty) {
            origin = '${refererUri.scheme}://${refererUri.host}';
          }
          break;
        }
      }
    }
    final parsedOrigin = origin == null ? null : Uri.tryParse(origin);
    if (parsedOrigin != null &&
        parsedOrigin.scheme == 'https' &&
        parsedOrigin.host.toLowerCase().endsWith('youtube.com')) {
      return '${parsedOrigin.scheme}://${parsedOrigin.host}';
    }
    return 'https://m.youtube.com';
  }

  String _headerValueIgnoreCase(Map<String, String>? headers, String name) {
    final source = headers ?? const <String, String>{};
    final target = name.toLowerCase();
    for (final entry in source.entries) {
      if (entry.key.toLowerCase() == target) {
        return entry.value.trim();
      }
    }
    return '';
  }

  String _blockedResponseAllowMethods(Map<String, String>? requestHeaders) {
    final requestedMethod = _headerValueIgnoreCase(
      requestHeaders,
      'Access-Control-Request-Method',
    );
    if (requestedMethod.isNotEmpty) {
      return 'GET, POST, OPTIONS, $requestedMethod';
    }
    return 'GET, POST, OPTIONS';
  }

  String _blockedResponseAllowHeaders(Map<String, String>? requestHeaders) {
    final requestedHeaders = _headerValueIgnoreCase(
      requestHeaders,
      'Access-Control-Request-Headers',
    );
    if (requestedHeaders.isNotEmpty) {
      return requestedHeaders;
    }
    // Keep this explicit for YouTube ad preflight flow.
    return 'x-goog-visitor-id, content-type, authorization, x-client-data';
  }

  WebResourceResponse _blockedResponse(
    String reason, {
    Map<String, String>? requestHeaders,
  }) {
    final allowOrigin = _blockedResponseCorsOrigin(requestHeaders);
    final allowMethods = _blockedResponseAllowMethods(requestHeaders);
    final allowHeaders = _blockedResponseAllowHeaders(requestHeaders);
    _logAdblockTrace('respond blocked status=204 reason=$reason');
    return WebResourceResponse(
      statusCode: 204,
      reasonPhrase: 'No Content',
      contentType: 'text/plain',
      contentEncoding: 'utf-8',
      data: Uint8List(0),
      headers: <String, String>{
        'Cache-Control': 'no-store',
        'Vary': 'Origin',
        'Access-Control-Allow-Origin': allowOrigin,
        'Access-Control-Allow-Credentials': 'true',
        'Access-Control-Allow-Methods': allowMethods,
        'Access-Control-Allow-Headers': allowHeaders,
      },
    );
  }

  WebResourceResponse _redirectedResponse(
    String dataUrl, {
    Map<String, String>? requestHeaders,
  }) {
    final allowOrigin = _blockedResponseCorsOrigin(requestHeaders);
    final allowMethods = _blockedResponseAllowMethods(requestHeaders);
    final allowHeaders = _blockedResponseAllowHeaders(requestHeaders);
    try {
      final uri = Uri.parse(dataUrl);
      final uriData = UriData.fromUri(uri);
      final bytes = Uint8List.fromList(uriData.contentAsBytes());
      final mimeType = uriData.mimeType.trim();
      final charset = uriData.charset.trim();
      _logAdblockTrace(
        'respond redirected status=200 mime=${mimeType.isEmpty ? 'text/plain' : mimeType} bytes=${bytes.length}',
      );
      return WebResourceResponse(
        statusCode: 200,
        reasonPhrase: 'OK',
        contentType: mimeType.isEmpty ? 'text/plain' : mimeType,
        contentEncoding: charset.isEmpty ? 'utf-8' : charset,
        data: bytes,
        headers: <String, String>{
          'Cache-Control': 'no-store',
          'Vary': 'Origin',
          'Access-Control-Allow-Origin': allowOrigin,
          'Access-Control-Allow-Credentials': 'true',
          'Access-Control-Allow-Methods': allowMethods,
          'Access-Control-Allow-Headers': allowHeaders,
        },
      );
    } catch (_) {
      _logAdblockTrace('redirect payload decode failed -> fallback block');
      return _blockedResponse(
        'Redirect payload decode failed',
        requestHeaders: requestHeaders,
      );
    }
  }

  WebResourceResponse _rewrittenUrlResponse(
    String rewrittenUrl, {
    Map<String, String>? requestHeaders,
  }) {
    final allowOrigin = _blockedResponseCorsOrigin(requestHeaders);
    final allowMethods = _blockedResponseAllowMethods(requestHeaders);
    final allowHeaders = _blockedResponseAllowHeaders(requestHeaders);
    _logAdblockTrace('respond rewritten status=307 url=$rewrittenUrl');
    return WebResourceResponse(
      statusCode: 307,
      reasonPhrase: 'Temporary Redirect',
      contentType: 'text/plain',
      contentEncoding: 'utf-8',
      data: Uint8List(0),
      headers: <String, String>{
        'Location': rewrittenUrl,
        'Cache-Control': 'no-store',
        'Vary': 'Origin',
        'Access-Control-Allow-Origin': allowOrigin,
        'Access-Control-Allow-Credentials': 'true',
        'Access-Control-Allow-Methods': allowMethods,
        'Access-Control-Allow-Headers': allowHeaders,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final compactForPiP = _isInPiPMode || _isPreparingPiPLayout;
    final packageEnabled = _packageStatus.hasPackage;
    final packageDaysLabel = _packageStatus.remainingDaysLabel;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          top: !compactForPiP,
          bottom: false,
          child: Column(
            children: <Widget>[
              if (!compactForPiP)
                BrowserControls(
                  canGoBack: packageEnabled && _canGoBack,
                  isLoading: _isLoading,
                  isVideoPlaying: _videoPlaying,
                  title: _packageStatus.tabStatusLabel,
                  featuresEnabled: packageEnabled,
                  pipEnabled: packageEnabled && _settingsController.pipEnabled,
                  onEnterPiP: _onEnterPiPPressed,
                  onBack: _goBack,
                  onRefresh: _reload,
                  onAccount: _openAccount,
                ),
              if (!compactForPiP && _isLoading)
                LinearProgressIndicator(
                  minHeight: 2,
                  value: _progress >= 100 ? null : _progress / 100,
                ),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !packageEnabled || !_adblockRuntimeReady,
                        child: _errorMessage != null
                            ? BrowserErrorView(
                                message: _errorMessage!,
                                onRetry: _retry,
                              )
                            : Stack(
                                children: <Widget>[
                                  InAppWebView(
                                    initialUrlRequest: URLRequest(
                                      url: WebUri(AppConfig.homeUri.toString()),
                                    ),
                                    initialUserScripts:
                                        _buildInitialUserScripts(),
                                    initialSettings: InAppWebViewSettings(
                                      javaScriptEnabled: true,
                                      domStorageEnabled: true,
                                      databaseEnabled: true,
                                      cacheEnabled: true,
                                      mediaPlaybackRequiresUserGesture: false,
                                      allowsInlineMediaPlayback: true,
                                      allowBackgroundAudioPlaying: true,
                                      javaScriptCanOpenWindowsAutomatically:
                                          false,
                                      supportZoom: false,
                                      useShouldOverrideUrlLoading: true,
                                      useShouldInterceptRequest: true,
                                      useShouldInterceptAjaxRequest: true,
                                      useShouldInterceptFetchRequest: true,
                                      safeBrowsingEnabled: true,
                                      thirdPartyCookiesEnabled: true,
                                      allowFileAccessFromFileURLs: false,
                                      allowUniversalAccessFromFileURLs: false,
                                    ),
                                    onWebViewCreated: (controller) {
                                      _webViewController = controller;
                                      if (_adblockRuntimeReady) {
                                        setState(() {
                                          _adblockRuntimeReady = false;
                                        });
                                      }
                                      unawaited(
                                        _prepareAdblockRuntime(controller),
                                      );
                                      controller.addJavaScriptHandler(
                                        handlerName: 'go_playVideoState',
                                        callback: (arguments) {
                                          if (arguments.isEmpty ||
                                              arguments.first is! Map) {
                                            return null;
                                          }
                                          final payload =
                                              Map<String, dynamic>.from(
                                                arguments.first as Map,
                                              );
                                          _logVideoStatePayload(
                                            payload,
                                            source: 'go_playVideoState',
                                          );
                                          final videoWidth = _toPositiveInt(
                                            payload['videoWidth'],
                                          );
                                          final videoHeight = _toPositiveInt(
                                            payload['videoHeight'],
                                          );
                                          final videoRectLeft = _toPositiveInt(
                                            payload['videoRectLeft'],
                                          );
                                          final videoRectTop = _toPositiveInt(
                                            payload['videoRectTop'],
                                          );
                                          final videoRectRight = _toPositiveInt(
                                            payload['videoRectRight'],
                                          );
                                          final videoRectBottom =
                                              _toPositiveInt(
                                                payload['videoRectBottom'],
                                              );
                                          final durationMs = _toPositiveInt(
                                            payload['durationMs'],
                                          );
                                          final positionMs = _toPositiveInt(
                                            payload['positionMs'],
                                          );
                                          final title = (payload['title'] ?? '')
                                              .toString()
                                              .trim();
                                          final author =
                                              (payload['author'] ?? '')
                                                  .toString()
                                                  .trim();
                                          final videoId =
                                              (payload['videoId'] ?? '')
                                                  .toString()
                                                  .trim();
                                          if (videoId.isNotEmpty) {
                                            _lastObservedVideoId = videoId;
                                          }
                                          _updateVideoState(
                                            isPlaying:
                                                payload['isPlaying'] == true,
                                            isFullscreen:
                                                payload['isFullscreen'] == true,
                                            videoWidth: videoWidth,
                                            videoHeight: videoHeight,
                                            videoRectLeft: videoRectLeft,
                                            videoRectTop: videoRectTop,
                                            videoRectRight: videoRectRight,
                                            videoRectBottom: videoRectBottom,
                                            title: title,
                                            author: author,
                                            durationMs: durationMs,
                                            positionMs: positionMs,
                                            hasNext: payload['hasNext'] == true,
                                            videoId: videoId,
                                          );
                                          final eventName =
                                              (payload['event'] ?? '')
                                                  .toString()
                                                  .trim();
                                          final pageVisibility =
                                              (payload['pageVisibility'] ?? '')
                                                  .toString()
                                                  .trim();
                                          if (!_isInPiPMode &&
                                              pageVisibility == 'visible' &&
                                              eventName ==
                                                  'doc:visibilitychange') {
                                            unawaited(
                                              _checkAndRepairStalePiPLayout(
                                                reason:
                                                    'doc_visibility_visible',
                                                force: true,
                                              ),
                                            );
                                          }
                                          return null;
                                        },
                                      );
                                      controller.addJavaScriptHandler(
                                        handlerName: 'go_playPlaybackDebug',
                                        callback: (arguments) {
                                          if (arguments.isEmpty ||
                                              arguments.first is! Map) {
                                            return null;
                                          }
                                          final payload =
                                              Map<String, dynamic>.from(
                                                arguments.first as Map,
                                              );
                                          _handlePlaybackDebugPayload(payload);
                                          return null;
                                        },
                                      );
                                      controller.addJavaScriptHandler(
                                        handlerName: 'go_playAdblockDebug',
                                        callback: (arguments) {
                                          if (arguments.isEmpty ||
                                              arguments.first is! Map) {
                                            return null;
                                          }
                                          final payload =
                                              Map<String, dynamic>.from(
                                                arguments.first as Map,
                                              );
                                          _logAdblockJsPayload(payload);
                                          _adblockService.onAdblockDebugSignal(
                                            payload,
                                            pageUri: _currentMainFrameUri,
                                          );
                                          return null;
                                        },
                                      );
                                      unawaited(
                                        _injectVideoStateScript(force: true),
                                      );
                                      unawaited(_updateCanGoBack());
                                    },
                                    shouldOverrideUrlLoading:
                                        (_, navigationAction) async {
                                          if (navigationAction.isForMainFrame ==
                                              false) {
                                            return NavigationActionPolicy.ALLOW;
                                          }
                                          final uri = _toUri(
                                            navigationAction.request.url,
                                          );
                                          final result = _navigationInterceptor
                                              .evaluate(uri);
                                          if (result.isAllowed) {
                                            _rememberMainFrameUri(uri);
                                            return NavigationActionPolicy.ALLOW;
                                          }
                                          _showBlockedNavigation(
                                            uri,
                                            result.reason,
                                          );
                                          return NavigationActionPolicy.CANCEL;
                                        },
                                    shouldInterceptRequest: (controller, request) async {
                                      final uri = _toUri(request.url);
                                      if (uri == null) {
                                        return null;
                                      }

                                      if (!_domainPolicyService
                                          .isRequestAllowed(uri)) {
                                        _logAdblockTrace(
                                          'request intercept block reason=domain_policy uri=${uri.host}${uri.path}',
                                        );
                                        return _blockedResponse(
                                          'Blocked by domain policy',
                                          requestHeaders: request.headers,
                                        );
                                      }

                                      // Never adblock the top-level navigation request.
                                      // Keeping this fail-open protects page stability.
                                      if (request.isForMainFrame != false) {
                                        _rememberMainFrameUri(uri);
                                        return null;
                                      }

                                      if (uri.scheme.toLowerCase() != 'https') {
                                        return null;
                                      }

                                      final sourceUriFromHeader =
                                          _sourceUriFromRequest(request);
                                      final resourceType =
                                          _resourceTypeFromRequest(
                                            request,
                                            uri,
                                          );

                                      final adblockDecision =
                                          await _shouldBlockByPolicyAndAdblock(
                                            controller,
                                            uri,
                                            resourceType: resourceType,
                                            sourceUri: sourceUriFromHeader,
                                          );
                                      if ((adblockDecision.redirectDataUrl ??
                                              '')
                                          .isNotEmpty) {
                                        _logAdblockTrace(
                                          'request intercept redirect reason=${adblockDecision.reason} uri=${uri.host}${uri.path} type=$resourceType',
                                        );
                                        return _redirectedResponse(
                                          adblockDecision.redirectDataUrl!,
                                          requestHeaders: request.headers,
                                        );
                                      }
                                      if ((adblockDecision.rewrittenUrl ?? '')
                                          .isNotEmpty) {
                                        _logAdblockTrace(
                                          'request intercept rewrite reason=${adblockDecision.reason} uri=${uri.host}${uri.path} type=$resourceType',
                                        );
                                        return _rewrittenUrlResponse(
                                          adblockDecision.rewrittenUrl!,
                                          requestHeaders: request.headers,
                                        );
                                      }
                                      if (adblockDecision.blocked) {
                                        _logAdblockTrace(
                                          'request intercept block reason=${adblockDecision.reason} uri=${uri.host}${uri.path} type=$resourceType',
                                        );
                                        return _blockedResponse(
                                          'Blocked by adblock (${adblockDecision.reason})',
                                          requestHeaders: request.headers,
                                        );
                                      }
                                      return null;
                                    },
                                    shouldInterceptAjaxRequest:
                                        _interceptAjaxRequest,
                                    shouldInterceptFetchRequest:
                                        _interceptFetchRequest,
                                    onCreateWindow:
                                        (controller, createWindowAction) async {
                                          final uri = _toUri(
                                            createWindowAction.request.url,
                                          );
                                          final result = _navigationInterceptor
                                              .evaluate(uri);
                                          if (!result.isAllowed) {
                                            _showBlockedNavigation(
                                              uri,
                                              result.reason,
                                            );
                                            return false;
                                          }

                                          if (uri != null) {
                                            await controller.loadUrl(
                                              urlRequest: URLRequest(
                                                url: WebUri(uri.toString()),
                                              ),
                                            );
                                          }
                                          return false;
                                        },
                                    onLoadStart: (controller, uri) {
                                      _cancelPendingAutoNext(
                                        reason: 'load_start',
                                      );
                                      _logNavigationEvent(
                                        'loadStart',
                                        _toUri(uri),
                                      );
                                      _markMainFrameNavigation(
                                        uri,
                                        resetRetryBudget: false,
                                      );
                                      setState(() {
                                        _isLoading = true;
                                        _errorMessage = null;
                                      });
                                      unawaited(
                                        _adblockService.onPageStarted(
                                          _toUri(uri),
                                        ),
                                      );
                                    },
                                    onLoadStop: (controller, uri) async {
                                      if (!mounted) {
                                        return;
                                      }
                                      final resolvedUri = _toUri(uri);
                                      _logNavigationEvent(
                                        'loadStop',
                                        resolvedUri,
                                      );
                                      _rememberMainFrameUri(resolvedUri);
                                      setState(() {
                                        _isLoading = false;
                                        _progress = 100;
                                      });
                                      if (_shouldSkipDuplicateLoadStop(
                                        resolvedUri,
                                      )) {
                                        _logNavigationEvent(
                                          'loadStop(skip_duplicate)',
                                          resolvedUri,
                                        );
                                        await _updateCanGoBack();
                                        return;
                                      }
                                      await _restoreForPiPExitIfNeeded(
                                        reason: 'load_stop_exit_fallback',
                                      );
                                      await _injectVideoStateScript(
                                        force: true,
                                      );
                                      await _adblockService.onPageFinished(
                                        resolvedUri,
                                      );
                                      await _applyDocumentCspIfNeeded(
                                        resolvedUri,
                                      );
                                      await _syncBackgroundPlaybackGuard(
                                        reason: 'load_stop',
                                      );
                                      await _checkAndRepairStalePiPLayout(
                                        reason: 'load_stop',
                                      );
                                      await _updateCanGoBack();
                                    },
                                    onUpdateVisitedHistory:
                                        (controller, uri, isReload) {
                                          _rememberMainFrameUri(_toUri(uri));
                                          unawaited(_injectVideoStateScript());
                                          unawaited(_syncAdblockScript());
                                          unawaited(_updateCanGoBack());
                                        },
                                    onProgressChanged: (controller, progress) {
                                      if (!mounted) {
                                        return;
                                      }
                                      setState(() {
                                        _progress = progress;
                                        _isLoading = progress < 100;
                                      });
                                    },
                                    onEnterFullscreen: (controller) {
                                      _updateVideoState(
                                        isPlaying: _videoPlaying,
                                        isFullscreen: true,
                                        videoWidth: _videoWidth,
                                        videoHeight: _videoHeight,
                                        videoRectLeft: _videoRectLeft,
                                        videoRectTop: _videoRectTop,
                                        videoRectRight: _videoRectRight,
                                        videoRectBottom: _videoRectBottom,
                                        title: _mediaTitle,
                                        author: _mediaAuthor,
                                        durationMs: _durationMs,
                                        positionMs: _positionMs,
                                        hasNext: _hasNext,
                                        videoId: _currentKnownVideoId(),
                                      );
                                    },
                                    onExitFullscreen: (controller) {
                                      _updateVideoState(
                                        isPlaying: _videoPlaying,
                                        isFullscreen: false,
                                        videoWidth: _videoWidth,
                                        videoHeight: _videoHeight,
                                        videoRectLeft: _videoRectLeft,
                                        videoRectTop: _videoRectTop,
                                        videoRectRight: _videoRectRight,
                                        videoRectBottom: _videoRectBottom,
                                        title: _mediaTitle,
                                        author: _mediaAuthor,
                                        durationMs: _durationMs,
                                        positionMs: _positionMs,
                                        hasNext: _hasNext,
                                        videoId: _currentKnownVideoId(),
                                      );
                                    },
                                    onReceivedError: (controller, request, error) {
                                      if (request.isForMainFrame != true) {
                                        return;
                                      }
                                      if (!mounted) {
                                        return;
                                      }
                                      final failedUri = _toUri(request.url);
                                      _logNavigationEvent(
                                        'receivedError(${error.type.toValue()})',
                                        failedUri,
                                      );
                                      _markMainFrameNavigation(
                                        failedUri,
                                        resetRetryBudget: false,
                                      );
                                      if (_isDnsResolveError(error) &&
                                          _dnsAutoRetryAttempt <
                                              _maxDnsAutoRetryAttempts) {
                                        unawaited(
                                          _autoRetryAfterDnsError(failedUri),
                                        );
                                        return;
                                      }
                                      setState(() {
                                        _isLoading = false;
                                        _errorMessage = error.description;
                                      });
                                    },
                                    onReceivedHttpError:
                                        (controller, request, response) {
                                          if (request.isForMainFrame != true) {
                                            return;
                                          }
                                          if (!mounted) {
                                            return;
                                          }
                                          _logNavigationEvent(
                                            'receivedHttpError(${response.statusCode})',
                                            _toUri(request.url),
                                          );
                                          setState(() {
                                            _isLoading = false;
                                            _errorMessage =
                                                'HTTP ${response.statusCode}: ${response.reasonPhrase ?? 'Unknown'}';
                                          });
                                        },
                                    onPermissionRequest:
                                        (controller, permissionRequest) async {
                                          return PermissionResponse(
                                            resources:
                                                permissionRequest.resources,
                                            action:
                                                PermissionResponseAction.GRANT,
                                          );
                                        },
                                  ),
                                  if (_autoNextTransitioning && !_isInPiPMode)
                                    Positioned.fill(
                                      child: ColoredBox(
                                        color: Colors.black,
                                        child: Center(
                                          child: SizedBox.square(
                                            dimension: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                    if (!packageEnabled)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const Icon(
                                      Icons.lock_clock_outlined,
                                      color: Colors.white,
                                      size: 34,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'NO PACKAGE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      packageDaysLabel,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    FilledButton(
                                      onPressed: _openAccount,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFE62117,
                                        ),
                                      ),
                                      child: const Text('ไปที่ Account'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (packageEnabled && !_adblockRuntimeReady)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.16),
                          ),
                          child: const Center(
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
