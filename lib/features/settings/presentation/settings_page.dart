import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../../auth/domain/session_package_status.dart';
import '../../session/session_service.dart';
import '../settings_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settingsController,
    required this.sessionService,
    required this.authController,
    super.key,
  });

  final SettingsController settingsController;
  final SessionService sessionService;
  final AuthController authController;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isClearing = false;

  Future<void> _clearSessionAndCache() async {
    if (_isClearing) {
      return;
    }

    setState(() {
      _isClearing = true;
    });

    try {
      await widget.sessionService.clearSessionAndCache();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session and cache cleared')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          widget.settingsController,
          widget.authController,
        ]),
        builder: (context, _) {
          final packageStatus = SessionPackageStatus.fromExpiresAt(
            widget.authController.currentSubscription?.expiryDate,
          );
          final featureEnabled = packageStatus.hasPackage;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Signed In Account'),
                subtitle: Text(
                  widget.authController.currentUser?.email ?? 'Not signed in',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Adblock'),
                subtitle: const Text(
                  'Enable Brave-style request filtering layer',
                ),
                value: widget.settingsController.adblockEnabled,
                onChanged: featureEnabled
                    ? widget.settingsController.setAdblockEnabled
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Picture-in-Picture'),
                subtitle: const Text(
                  'Enter PiP when Home is pressed during video playback',
                ),
                value: widget.settingsController.pipEnabled,
                onChanged: featureEnabled
                    ? widget.settingsController.setPiPEnabled
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Background Playback'),
                subtitle: const Text(
                  'Keep playing with lock-screen and notification controls',
                ),
                value: widget.settingsController.backgroundPlaybackEnabled,
                onChanged: featureEnabled
                    ? widget.settingsController.setBackgroundPlaybackEnabled
                    : null,
              ),
              if (!featureEnabled)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'NO PACKAGE: ฟีเจอร์ถูกปิดจนกว่าจะต่ออายุ',
                    style: TextStyle(
                      color: Color(0xFFE62117),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: featureEnabled && !_isClearing
                    ? _clearSessionAndCache
                    : null,
                icon: _isClearing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_sweep_outlined),
                label: const Text('Clear Session / Cache'),
              ),
            ],
          );
        },
      ),
    );
  }
}
