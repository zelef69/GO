import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../shared/constants/channel_constants.dart';

/// High-level risk decision returned by native integrity checks.
enum SecurityDecision { allow, highRisk, block }

/// Structured result used by startup checks and randomized runtime checks.
@immutable
class SecurityCheckResult {
  const SecurityCheckResult({
    required this.decision,
    required this.reasonCode,
    required this.checkpoint,
    this.highRiskSignals = const <String>[],
  });

  factory SecurityCheckResult.fromMap(
    Map<Object?, Object?> raw, {
    required String fallbackCheckpoint,
  }) {
    final decisionRaw = (raw['decision'] ?? '').toString().trim().toLowerCase();
    final decision = switch (decisionRaw) {
      'block' => SecurityDecision.block,
      'high_risk' => SecurityDecision.highRisk,
      _ => SecurityDecision.allow,
    };
    final highRiskRaw = raw['highRiskSignals'];
    final highRiskSignals = highRiskRaw is List
        ? highRiskRaw.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    return SecurityCheckResult(
      decision: decision,
      reasonCode: (raw['reasonCode'] ?? 'UNKNOWN').toString(),
      checkpoint: (raw['checkpoint'] ?? fallbackCheckpoint).toString(),
      highRiskSignals: highRiskSignals,
    );
  }

  final SecurityDecision decision;
  final String reasonCode;
  final String checkpoint;
  final List<String> highRiskSignals;

  bool get isBlocked => decision == SecurityDecision.block;
}

class SecurityCheckpointException implements Exception {
  SecurityCheckpointException(this.message);

  final String message;

  @override
  String toString() => 'SecurityCheckpointException($message)';
}

/// Central security orchestrator.
///
/// Responsibilities:
/// - Run startup checks before app UI loads.
/// - Trigger randomized runtime checks (timer + app resume).
/// - Expose a single sensitive-action checkpoint API.
/// - Fail closed on critical native detections in release builds.
class SecurityService with WidgetsBindingObserver {
  SecurityService._();

  static final SecurityService instance = SecurityService._();

  final MethodChannel _channel = const MethodChannel(ChannelConstants.security);
  final Random _random = Random.secure();
  final ValueNotifier<SecurityCheckResult?> latestResult =
      ValueNotifier<SecurityCheckResult?>(null);

  Timer? _runtimeTimer;
  bool _runtimeMonitoringStarted = false;
  bool _blockRaised = false;

  bool get isBlocked => _blockRaised;

  Future<SecurityCheckResult> initializeSecurity() async {
    final result = await _runNativeCheck(
      method: ChannelConstants.methodInitializeSecurity,
      checkpoint: 'startup',
    );
    _handleResult(result);
    return result;
  }

  Future<void> checkpointSensitiveAction(String action) async {
    final result = await _runNativeCheck(
      method: ChannelConstants.methodRunSecurityCheck,
      checkpoint: 'sensitive:$action',
      arguments: <String, Object?>{'checkpoint': 'sensitive:$action'},
    );
    _handleResult(result);
    if (result.isBlocked) {
      throw SecurityCheckpointException('Blocked at $action');
    }
  }

  Future<Map<String, dynamic>> buildTrustSignal({
    required String nonce,
    String context = 'generic',
  }) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      ChannelConstants.methodBuildTrustSignal,
      <String, Object?>{'nonce': nonce, 'context': context},
    );
    return raw ?? const <String, dynamic>{};
  }

  void startRuntimeMonitoring() {
    if (_runtimeMonitoringStarted) {
      return;
    }
    _runtimeMonitoringStarted = true;
    WidgetsBinding.instance.addObserver(this);
    _scheduleNextRuntimeCheck();
  }

  void stopRuntimeMonitoring() {
    _runtimeTimer?.cancel();
    _runtimeTimer = null;
    if (_runtimeMonitoringStarted) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _runtimeMonitoringStarted = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runRuntimeCheckpoint(checkpoint: 'lifecycle:resumed'));
    }
  }

  Future<void> _runRuntimeCheckpoint({required String checkpoint}) async {
    final result = await _runNativeCheck(
      method: ChannelConstants.methodRunSecurityCheck,
      checkpoint: checkpoint,
      arguments: <String, Object?>{'checkpoint': checkpoint},
    );
    _handleResult(result);
    if (!_blockRaised) {
      _scheduleNextRuntimeCheck();
    }
  }

  void _scheduleNextRuntimeCheck() {
    _runtimeTimer?.cancel();
    if (_blockRaised) {
      return;
    }
    final jitterSeconds = 20 + _random.nextInt(41);
    _runtimeTimer = Timer(Duration(seconds: jitterSeconds), () {
      unawaited(_runRuntimeCheckpoint(checkpoint: 'timer:jitter'));
    });
  }

  Future<SecurityCheckResult> _runNativeCheck({
    required String method,
    required String checkpoint,
    Map<String, Object?>? arguments,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        method,
        arguments,
      );
      if (raw == null) {
        if (kReleaseMode) {
          return SecurityCheckResult(
            decision: SecurityDecision.block,
            reasonCode: 'SECURITY_CHANNEL_NULL',
            checkpoint: checkpoint,
          );
        }
        return SecurityCheckResult(
          decision: SecurityDecision.highRisk,
          reasonCode: 'SECURITY_CHANNEL_NULL',
          checkpoint: checkpoint,
          highRiskSignals: const <String>['security_channel_null_response'],
        );
      }
      return SecurityCheckResult.fromMap(raw, fallbackCheckpoint: checkpoint);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[GO_PLAY-SecurityService] $checkpoint -> channel error: $error',
        );
        debugPrint(stackTrace.toString());
      }
      if (kReleaseMode) {
        return SecurityCheckResult(
          decision: SecurityDecision.block,
          reasonCode: 'SECURITY_CHANNEL_EXCEPTION',
          checkpoint: checkpoint,
        );
      }
      return SecurityCheckResult(
        decision: SecurityDecision.highRisk,
        reasonCode: 'SECURITY_CHANNEL_EXCEPTION',
        checkpoint: checkpoint,
        highRiskSignals: const <String>['security_channel_exception'],
      );
    }
  }

  void _handleResult(SecurityCheckResult result) {
    latestResult.value = result;
    if (kDebugMode) {
      debugPrint(
        '[GO_PLAY-SecurityService] checkpoint=${result.checkpoint} decision=${result.decision.name} reason=${result.reasonCode} signals=${result.highRiskSignals.join(",")}',
      );
    }
    if (result.isBlocked) {
      _blockRaised = true;
      _runtimeTimer?.cancel();
      _runtimeTimer = null;
    }
  }
}
