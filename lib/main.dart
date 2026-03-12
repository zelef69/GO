import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/config/app_dependencies.dart';
import 'services/security_service.dart';

bool _terminationScheduled = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final securityService = SecurityService.instance;
  final startupSecurity = await securityService.initializeSecurity();
  if (startupSecurity.isBlocked) {
    runApp(
      _SecurityBlockedApp(
        debugReason: kDebugMode ? startupSecurity.reasonCode : null,
      ),
    );
    _scheduleSafeTermination();
    return;
  }

  Object? firebaseInitError;
  try {
    await Firebase.initializeApp();
  } catch (error) {
    firebaseInitError = error;
  }

  if (firebaseInitError != null) {
    runApp(
      _BootstrapErrorApp(
        error: kDebugMode ? firebaseInitError.toString() : null,
      ),
    );
    return;
  }

  securityService.startRuntimeMonitoring();
  final dependencies = AppDependencies.create();
  runApp(
    _SecurityRuntimeGate(
      securityService: securityService,
      child: GoPlayApp(dependencies: dependencies),
    ),
  );
}

class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({required this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Firebase initialization failed.\n'
              'Please add Firebase config files and restart app.'
              '${error == null ? '' : '\n\n$error'}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityRuntimeGate extends StatelessWidget {
  const _SecurityRuntimeGate({
    required this.securityService,
    required this.child,
  });

  final SecurityService securityService;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SecurityCheckResult?>(
      valueListenable: securityService.latestResult,
      child: child,
      builder: (context, _, childWidget) {
        if (securityService.isBlocked) {
          _scheduleSafeTermination();
          return _SecurityBlockedApp(
            debugReason: kDebugMode
                ? securityService.latestResult.value?.reasonCode
                : null,
          );
        }
        return childWidget ?? child;
      },
    );
  }
}

class _SecurityBlockedApp extends StatelessWidget {
  const _SecurityBlockedApp({this.debugReason});

  final String? debugReason;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Security check failed.\nApplication cannot continue.'
              '${debugReason == null ? '' : '\n\n$debugReason'}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

void _scheduleSafeTermination() {
  if (_terminationScheduled) {
    return;
  }
  _terminationScheduled = true;
  Future<void>.delayed(const Duration(seconds: 2), () async {
    await SystemChannels.platform.invokeMethod<void>('SystemNavigator.pop');
  });
}
