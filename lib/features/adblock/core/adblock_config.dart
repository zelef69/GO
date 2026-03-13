import '../../../app/config/app_config.dart';

class AdblockConfig {
  const AdblockConfig({
    required this.enabled,
    required this.cosmeticFilteringEnabled,
    required this.scriptletsEnabled,
    required this.serviceWorkerInterceptionEnabled,
    required this.crowdLearningEnabled,
    required this.crowdSyncEnabled,
    required this.crowdPrecheckEnabled,
    required this.debugMode,
    required this.remoteListRefreshEnabled,
    required this.remoteListRefreshInterval,
    required this.region,
    required this.selectedListIds,
    required this.braveCatalogEnabled,
    required this.braveCatalogUrl,
    required this.braveResourcesEnabled,
    required this.braveResourcesUrl,
    required this.firstPartyHeuristicsEnabled,
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
      serviceWorkerInterceptionEnabled: true,
      crowdLearningEnabled: true,
      crowdSyncEnabled: true,
      crowdPrecheckEnabled: true,
      debugMode: debugMode,
      remoteListRefreshEnabled: true,
      remoteListRefreshInterval: AppConfig.remoteFilterRefreshInterval,
      region: AppConfig.defaultFilterRegion,
      selectedListIds: const <String>[],
      braveCatalogEnabled: true,
      braveCatalogUrl: AppConfig.braveListCatalogUrl,
      braveResourcesEnabled: true,
      braveResourcesUrl: AppConfig.braveResourcesUrl,
      firstPartyHeuristicsEnabled: true,
      allowlistedHosts: const <String>{},
      blocklistedHosts: const <String>{},
    );
  }

  final bool enabled;
  final bool cosmeticFilteringEnabled;
  final bool scriptletsEnabled;
  final bool serviceWorkerInterceptionEnabled;
  final bool crowdLearningEnabled;
  final bool crowdSyncEnabled;
  final bool crowdPrecheckEnabled;
  final bool debugMode;
  final bool remoteListRefreshEnabled;
  final Duration remoteListRefreshInterval;
  final String region;
  final List<String> selectedListIds;
  final bool braveCatalogEnabled;
  final String braveCatalogUrl;
  final bool braveResourcesEnabled;
  final String braveResourcesUrl;
  final bool firstPartyHeuristicsEnabled;
  final Set<String> allowlistedHosts;
  final Set<String> blocklistedHosts;

  AdblockConfig copyWith({
    bool? enabled,
    bool? cosmeticFilteringEnabled,
    bool? scriptletsEnabled,
    bool? serviceWorkerInterceptionEnabled,
    bool? crowdLearningEnabled,
    bool? crowdSyncEnabled,
    bool? crowdPrecheckEnabled,
    bool? debugMode,
    bool? remoteListRefreshEnabled,
    Duration? remoteListRefreshInterval,
    String? region,
    List<String>? selectedListIds,
    bool? braveCatalogEnabled,
    String? braveCatalogUrl,
    bool? braveResourcesEnabled,
    String? braveResourcesUrl,
    bool? firstPartyHeuristicsEnabled,
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
      crowdLearningEnabled: crowdLearningEnabled ?? this.crowdLearningEnabled,
      crowdSyncEnabled: crowdSyncEnabled ?? this.crowdSyncEnabled,
      crowdPrecheckEnabled: crowdPrecheckEnabled ?? this.crowdPrecheckEnabled,
      debugMode: debugMode ?? this.debugMode,
      remoteListRefreshEnabled:
          remoteListRefreshEnabled ?? this.remoteListRefreshEnabled,
      remoteListRefreshInterval:
          remoteListRefreshInterval ?? this.remoteListRefreshInterval,
      region: region ?? this.region,
      selectedListIds: selectedListIds ?? this.selectedListIds,
      braveCatalogEnabled: braveCatalogEnabled ?? this.braveCatalogEnabled,
      braveCatalogUrl: braveCatalogUrl ?? this.braveCatalogUrl,
      braveResourcesEnabled:
          braveResourcesEnabled ?? this.braveResourcesEnabled,
      braveResourcesUrl: braveResourcesUrl ?? this.braveResourcesUrl,
      firstPartyHeuristicsEnabled:
          firstPartyHeuristicsEnabled ?? this.firstPartyHeuristicsEnabled,
      allowlistedHosts: allowlistedHosts ?? this.allowlistedHosts,
      blocklistedHosts: blocklistedHosts ?? this.blocklistedHosts,
    );
  }
}
