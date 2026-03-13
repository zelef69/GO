import 'package:flutter/material.dart';

import '../../features/account/presentation/account_page.dart';
import '../../features/auth/presentation/auth_gate_page.dart';
import '../../features/player/presentation/player_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../config/app_dependencies.dart';

class AppRoutes {
  const AppRoutes._();

  static const String browser = '/';
  static const String account = '/account';
  static const String settings = '/settings';
  static const String player = '/player';
}

class AppRouter {
  AppRouter({required this.dependencies});

  final AppDependencies dependencies;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.account:
        return MaterialPageRoute<void>(
          builder: (_) => AccountPage(
            authController: dependencies.authController,
            updateService: dependencies.updateService,
          ),
          settings: settings,
        );
      case AppRoutes.settings:
        return MaterialPageRoute<void>(
          builder: (_) => SettingsPage(
            settingsController: dependencies.settingsController,
            sessionService: dependencies.sessionService,
            authController: dependencies.authController,
          ),
          settings: settings,
        );
      case AppRoutes.player:
        final args = settings.arguments;
        if (args is! PlayerPageArgs) {
          return MaterialPageRoute<void>(
            builder: (_) => AuthGatePage(dependencies: dependencies),
            settings: settings,
          );
        }
        if (args.launchInBackground) {
          return PageRouteBuilder<void>(
            settings: settings,
            opaque: false,
            barrierColor: Colors.transparent,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) =>
                PlayerPage(dependencies: dependencies, args: args),
          );
        }
        return MaterialPageRoute<void>(
          builder: (_) => PlayerPage(dependencies: dependencies, args: args),
          settings: settings,
        );
      case AppRoutes.browser:
      default:
        return MaterialPageRoute<void>(
          builder: (_) => AuthGatePage(dependencies: dependencies),
          settings: settings,
        );
    }
  }
}
