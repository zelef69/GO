import '../../features/adblock/adblock_engine_bridge.dart';
import '../../features/adblock/adblock_service.dart';
import '../../features/adblock/filter_list_loader.dart';
import '../../features/domain_lock/domain_policy_service.dart';
import '../../features/domain_lock/navigation_interceptor.dart';
import '../../features/pip/pip_channel.dart';
import '../../features/pip/pip_controller.dart';
import '../../features/session/session_service.dart';
import '../../features/settings/settings_controller.dart';
import 'app_config.dart';

class AppDependencies {
  AppDependencies._({
    required this.settingsController,
    required this.domainPolicyService,
    required this.navigationInterceptor,
    required this.adblockService,
    required this.pipChannel,
    required this.pipController,
    required this.sessionService,
  });

  final SettingsController settingsController;
  final DomainPolicyService domainPolicyService;
  final NavigationInterceptor navigationInterceptor;
  final AdblockService adblockService;
  final PiPChannel pipChannel;
  final PiPController pipController;
  final SessionService sessionService;

  factory AppDependencies.create() {
    final settingsController = SettingsController();
    final domainPolicyService = DomainPolicyService();
    final navigationInterceptor = NavigationInterceptor(
      domainPolicyService: domainPolicyService,
    );
    final adblockService = AdblockService(
      filterListLoader: FilterListLoader(assetPath: AppConfig.filterAssetPath),
      nativeEngineBridge: NativeAdblockEngineBridge(),
      fallbackEngineBridge: DartAdblockEngineBridge(),
      enabled: settingsController.adblockEnabled,
    );
    final pipChannel = PiPChannel();
    final pipController = PiPController(channel: pipChannel);
    final sessionService = SessionService();
    return AppDependencies._(
      settingsController: settingsController,
      domainPolicyService: domainPolicyService,
      navigationInterceptor: navigationInterceptor,
      adblockService: adblockService,
      pipChannel: pipChannel,
      pipController: pipController,
      sessionService: sessionService,
    );
  }
}
