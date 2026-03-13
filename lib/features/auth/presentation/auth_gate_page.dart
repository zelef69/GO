import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/config/app_dependencies.dart';
import '../../browser/presentation/browser_page.dart';
import '../auth_controller.dart';
import 'login_page.dart';

class AuthGatePage extends StatefulWidget {
  const AuthGatePage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends State<AuthGatePage> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    unawaited(widget.dependencies.authController.initialize());
  }

  @override
  Widget build(BuildContext context) {
    final authController = widget.dependencies.authController;
    return AnimatedBuilder(
      animation: authController,
      builder: (context, _) {
        switch (authController.status) {
          case AuthStatus.authenticated:
            return BrowserPage(dependencies: widget.dependencies);
          case AuthStatus.initializing:
          case AuthStatus.checkingSession:
          case AuthStatus.authenticating:
          case AuthStatus.unauthenticated:
          case AuthStatus.blocked:
          case AuthStatus.error:
            return LoginPage(authController: authController);
        }
      },
    );
  }
}
