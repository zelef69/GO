import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/config/setup_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  final dependencies = SetupDependencies.create();
  runApp(GoPlayApp(dependencies: dependencies));
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
