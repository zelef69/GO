import 'package:flutter/material.dart';

import '../../session/session_service.dart';
import '../settings_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settingsController,
    required this.sessionService,
    super.key,
  });

  final SettingsController settingsController;
  final SessionService sessionService;

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
        animation: widget.settingsController,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Adblock'),
                subtitle: const Text(
                  'Enable Brave-style request filtering layer',
                ),
                value: widget.settingsController.adblockEnabled,
                onChanged: widget.settingsController.setAdblockEnabled,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Picture-in-Picture'),
                subtitle: const Text(
                  'Enter PiP when Home is pressed during video playback',
                ),
                value: widget.settingsController.pipEnabled,
                onChanged: widget.settingsController.setPiPEnabled,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Background Playback'),
                subtitle: const Text(
                  'Keep playing with lock-screen and notification controls',
                ),
                value: widget.settingsController.backgroundPlaybackEnabled,
                onChanged:
                    widget.settingsController.setBackgroundPlaybackEnabled,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isClearing ? null : _clearSessionAndCache,
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
