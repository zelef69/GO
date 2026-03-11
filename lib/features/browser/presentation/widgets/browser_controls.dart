import 'package:flutter/material.dart';

class BrowserControls extends StatelessWidget {
  const BrowserControls({
    required this.canGoBack,
    required this.isLoading,
    required this.isVideoPlaying,
    required this.pipEnabled,
    required this.onEnterPiP,
    required this.onBack,
    required this.onRefresh,
    required this.onSettings,
    super.key,
  });

  final bool canGoBack;
  final bool isLoading;
  final bool isVideoPlaying;
  final bool pipEnabled;
  final VoidCallback onEnterPiP;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: canGoBack ? onBack : null,
              tooltip: 'Back',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: onRefresh,
              tooltip: 'Refresh',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'YouTube',
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                isVideoPlaying
                    ? Icons.play_circle_fill
                    : Icons.play_circle_outline,
                color: isVideoPlaying
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                icon: Icon(
                  pipEnabled
                      ? Icons.picture_in_picture_alt
                      : Icons.picture_in_picture_alt_outlined,
                ),
                onPressed: pipEnabled ? onEnterPiP : null,
                tooltip: 'PiP',
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: onSettings,
              tooltip: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
