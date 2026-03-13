class ChannelConstants {
  const ChannelConstants._();

  static const String pip = 'go_play/pip';
  static const String adblock = 'go_play/adblock';
  static const String security = 'go_play/security';
  static const String update = 'go_play/update';

  static const String methodSetPiPEnabled = 'setPiPEnabled';
  static const String methodSetBackgroundPlaybackEnabled =
      'setBackgroundPlaybackEnabled';
  static const String methodSetAppInForeground = 'setAppInForeground';
  static const String methodSetVideoState = 'setVideoState';
  static const String methodEnterPiPIfEligible = 'enterPiPIfEligible';
  static const String methodIsPiPSupported = 'isPiPSupported';
  static const String methodIsInPiPMode = 'isInPiPMode';

  static const String methodInitializeSecurity = 'initializeSecurity';
  static const String methodRunSecurityCheck = 'runSecurityCheck';
  static const String methodGetNativeSecrets = 'getNativeSecrets';
  static const String methodBuildTrustSignal = 'buildTrustSignal';

  static const String methodCanInstallPackages = 'canInstallPackages';
  static const String methodOpenUnknownAppsSettings = 'openUnknownAppsSettings';
  static const String methodInstallApk = 'installApk';
}
