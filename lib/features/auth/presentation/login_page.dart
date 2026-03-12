import 'dart:async';

import 'package:flutter/material.dart';

import '../auth_controller.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({required this.authController, super.key});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    final status = authController.status;
    final busy =
        status == AuthStatus.authenticating ||
        status == AuthStatus.checkingSession ||
        status == AuthStatus.initializing;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'GO_PLAY requires Google account sign-in.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your subscription is validated before entering the app.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if ((authController.message ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    authController.message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          unawaited(authController.signInWithGoogle());
                        },
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.g_mobiledata),
                  label: const Text('Sign In With Google'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          unawaited(authController.signOut());
                        },
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
