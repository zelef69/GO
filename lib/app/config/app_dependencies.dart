import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../features/adblock/adblock_engine_bridge.dart';
import '../../features/adblock/adblock_service.dart';
import '../../features/adblock/crowd/signature/signature_matcher.dart';
import '../../features/adblock/crowd/storage/learned_signature_db.dart';
import '../../features/adblock/crowd/storage/learned_signature_repository.dart';
import '../../features/adblock/crowd/sync/crowd_sync_service.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/data/auth_session_service.dart';
import '../../features/auth/data/device_id_service.dart';
import '../../features/auth/data/firebase_auth_service.dart';
import '../../features/auth/data/local_session_store.dart';
import '../../features/auth/data/subscription_service.dart';
import '../../features/domain_lock/domain_policy_service.dart';
import '../../features/domain_lock/navigation_interceptor.dart';
import '../../features/pip/pip_channel.dart';
import '../../features/pip/pip_controller.dart';
import '../../features/session/session_service.dart';
import '../../features/settings/settings_controller.dart';
import '../../services/native_secrets_service.dart';
import '../../services/secure_http_service.dart';
import '../../services/security_service.dart';
import '../../services/server_trust_service.dart';

class AppDependencies {
  AppDependencies._({
    required this.settingsController,
    required this.domainPolicyService,
    required this.navigationInterceptor,
    required this.adblockService,
    required this.pipChannel,
    required this.pipController,
    required this.sessionService,
    required this.firebaseAuthService,
    required this.subscriptionService,
    required this.authSessionService,
    required this.deviceIdService,
    required this.localSessionStore,
    required this.authController,
    required this.securityService,
    required this.nativeSecretsService,
    required this.secureHttpService,
    required this.serverTrustService,
  });

  final SettingsController settingsController;
  final DomainPolicyService domainPolicyService;
  final NavigationInterceptor navigationInterceptor;
  final AdblockService adblockService;
  final PiPChannel pipChannel;
  final PiPController pipController;
  final SessionService sessionService;
  final FirebaseAuthService firebaseAuthService;
  final SubscriptionService subscriptionService;
  final AuthSessionService authSessionService;
  final DeviceIdService deviceIdService;
  final LocalSessionStore localSessionStore;
  final AuthController authController;
  final SecurityService securityService;
  final NativeSecretsService nativeSecretsService;
  final SecureHttpService secureHttpService;
  final ServerTrustService serverTrustService;

  factory AppDependencies.create() {
    final settingsController = SettingsController();
    final domainPolicyService = DomainPolicyService();
    final navigationInterceptor = NavigationInterceptor(
      domainPolicyService: domainPolicyService,
    );
    final learnedSignatureRepository = LearnedSignatureRepository(
      database: LearnedSignatureDb(),
      matcher: const SignatureMatcher(),
    );
    final crowdSyncService = CrowdSyncService(
      functions: FirebaseFunctions.instance,
      repository: learnedSignatureRepository,
      debugMode: kDebugMode,
    );
    final adblockService = AdblockService(
      domainPolicyService: domainPolicyService,
      nativeEngineBridge: NativeAdblockEngineBridge(),
      fallbackEngineBridge: DartAdblockEngineBridge(),
      enabled: settingsController.adblockEnabled,
      learnedSignatureRepository: learnedSignatureRepository,
      crowdSyncService: crowdSyncService,
    );
    final pipChannel = PiPChannel();
    final pipController = PiPController(channel: pipChannel);
    final sessionService = SessionService();
    final firebaseAuthService = FirebaseAuthService();
    final subscriptionService = SubscriptionService();
    final authSessionService = AuthSessionService();
    final deviceIdService = DeviceIdService();
    final localSessionStore = LocalSessionStore();
    final securityService = SecurityService.instance;
    final nativeSecretsService = NativeSecretsService();
    final secureHttpService = SecureHttpService(
      nativeSecretsService: nativeSecretsService,
      securityService: securityService,
    );
    final serverTrustService = ServerTrustService(
      securityService: securityService,
    );
    final authController = AuthController(
      firebaseAuthService: firebaseAuthService,
      subscriptionService: subscriptionService,
      authSessionService: authSessionService,
      deviceIdService: deviceIdService,
      localSessionStore: localSessionStore,
      browserSessionService: sessionService,
    );
    return AppDependencies._(
      settingsController: settingsController,
      domainPolicyService: domainPolicyService,
      navigationInterceptor: navigationInterceptor,
      adblockService: adblockService,
      pipChannel: pipChannel,
      pipController: pipController,
      sessionService: sessionService,
      firebaseAuthService: firebaseAuthService,
      subscriptionService: subscriptionService,
      authSessionService: authSessionService,
      deviceIdService: deviceIdService,
      localSessionStore: localSessionStore,
      authController: authController,
      securityService: securityService,
      nativeSecretsService: nativeSecretsService,
      secureHttpService: secureHttpService,
      serverTrustService: serverTrustService,
    );
  }
}
