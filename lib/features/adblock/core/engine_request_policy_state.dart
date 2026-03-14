class SoftBlockGuardState {
  const SoftBlockGuardState({
    required this.windowStartedAtMs,
    required this.blockCountInWindow,
    required this.cooldownUntilMs,
  });

  final int windowStartedAtMs;
  final int blockCountInWindow;
  final int cooldownUntilMs;
}

class SoftLeakedRecoveryState {
  const SoftLeakedRecoveryState({
    required this.windowStartedAtMs,
    required this.blockedCountInWindow,
    required this.recoveryUntilMs,
  });

  final int windowStartedAtMs;
  final int blockedCountInWindow;
  final int recoveryUntilMs;
}

class AdSignalState {
  const AdSignalState({required this.activeUntilMs, required this.lastSource});

  final int activeUntilMs;
  final String lastSource;
}

class AdWindowEscalationState {
  const AdWindowEscalationState({
    required this.windowStartedAtMs,
    required this.allowCountInWindow,
    required this.blockUntilMs,
  });

  final int windowStartedAtMs;
  final int allowCountInWindow;
  final int blockUntilMs;
}

class PostBurstRecoveryState {
  const PostBurstRecoveryState({
    required this.windowStartedAtMs,
    required this.blockedCountInWindow,
    required this.recoveryUntilMs,
  });

  final int windowStartedAtMs;
  final int blockedCountInWindow;
  final int recoveryUntilMs;
}

class GoogleVideoOverblockState {
  const GoogleVideoOverblockState({
    required this.windowStartedAtMs,
    required this.requestCountInWindow,
    required this.blockedCountInWindow,
    required this.consecutiveFullBlockWindows,
    required this.failOpenUntilMs,
  });

  final int windowStartedAtMs;
  final int requestCountInWindow;
  final int blockedCountInWindow;
  final int consecutiveFullBlockWindows;
  final int failOpenUntilMs;
}
