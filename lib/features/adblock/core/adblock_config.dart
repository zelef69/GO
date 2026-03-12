import '../../../app/config/app_config.dart';

class AdblockConfig {
  const AdblockConfig({
    required this.enabled,
    required this.cosmeticFilteringEnabled,
    required this.scriptletsEnabled,
    required this.serviceWorkerInterceptionEnabled,
    required this.debugMode,
    required this.remoteListRefreshEnabled,
    required this.remoteListRefreshInterval,
    required this.region,
    required this.selectedListIds,
    required this.allowlistedHosts,
    required this.blocklistedHosts,
  });

  factory AdblockConfig.defaults({
    required bool enabled,
    required bool debugMode,
  }) {
    return AdblockConfig(
      enabled: enabled,
      cosmeticFilteringEnabled: true,
      scriptletsEnabled: true,
      serviceWorkerInterceptionEnabled: false,
      debugMode: debugMode,
      remoteListRefreshEnabled: false,
      remoteListRefreshInterval: AppConfig.remoteFilterRefreshInterval,
      region: AppConfig.defaultFilterRegion,
      selectedListIds: const <String>['basic'],
      allowlistedHosts: const <String>{},
      blocklistedHosts: const <String>{},
    );
  }

  final bool enabled;
  final bool cosmeticFilteringEnabled;
  final bool scriptletsEnabled;
  final bool serviceWorkerInterceptionEnabled;
  final bool debugMode;
  final bool remoteListRefreshEnabled;
  final Duration remoteListRefreshInterval;
  final String region;
  final List<String> selectedListIds;
  final Set<String> allowlistedHosts;
  final Set<String> blocklistedHosts;

  AdblockConfig copyWith({
    bool? enabled,
    bool? cosmeticFilteringEnabled,
    bool? scriptletsEnabled,
    bool? serviceWorkerInterceptionEnabled,
    bool? debugMode,
    bool? remoteListRefreshEnabled,
    Duration? remoteListRefreshInterval,
    String? region,
    List<String>? selectedListIds,
    Set<String>? allowlistedHosts,
    Set<String>? blocklistedHosts,
  }) {
    return AdblockConfig(
      enabled: enabled ?? this.enabled,
      cosmeticFilteringEnabled:
          cosmeticFilteringEnabled ?? this.cosmeticFilteringEnabled,
      scriptletsEnabled: scriptletsEnabled ?? this.scriptletsEnabled,
      serviceWorkerInterceptionEnabled:
          serviceWorkerInterceptionEnabled ??
          this.serviceWorkerInterceptionEnabled,
      debugMode: debugMode ?? this.debugMode,
      remoteListRefreshEnabled:
          remoteListRefreshEnabled ?? this.remoteListRefreshEnabled,
      remoteListRefreshInterval:
          remoteListRefreshInterval ?? this.remoteListRefreshInterval,
      region: region ?? this.region,
      selectedListIds: selectedListIds ?? this.selectedListIds,
      allowlistedHosts: allowlistedHosts ?? this.allowlistedHosts,
      blocklistedHosts: blocklistedHosts ?? this.blocklistedHosts,
    );
  }
}
