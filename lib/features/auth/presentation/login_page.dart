import 'dart:async';

import 'package:flutter/material.dart';

import '../auth_controller.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({required this.authController, super.key});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    final status = authController.status;
    final busy = status == AuthStatus.authenticating;
    final checking =
        status == AuthStatus.initializing ||
        status == AuthStatus.checkingSession;
    final theme = Theme.of(context);
    const youtubeRed = Color(0xFFFF2D2D);

    return Scaffold(
      backgroundColor: Colors.black,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF121212), Color(0xFF0A0A0A), Colors.black],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: ClipOval(
                        child: Image.asset(
                          'assets/pic/logo-v2.png',
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'GO_PLAY',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: youtubeRed,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Sign in with your Google account to continue.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Subscription is validated before entering the app.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if ((authController.message ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: 18),
                      Text(
                        authController.message!,
                        style: const TextStyle(
                          color: Color(0xFFFF6B6B),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (checking) ...<Widget>[
                      const SizedBox(height: 12),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: youtubeRed,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Checking session...',
                            style: TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 26),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: busy
                            ? null
                            : () {
                                unawaited(authController.signInWithGoogle());
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            if (busy)
                              const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.black87,
                                ),
                              )
                            else
                              const _GoogleMark(),
                            const SizedBox(width: 10),
                            Text(
                              busy ? 'Signing In...' : 'Sign in with Google',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () {
                              unawaited(authController.signOut());
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: youtubeRed,
                        side: const BorderSide(color: youtubeRed),
                      ),
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE4E4E4)),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}
