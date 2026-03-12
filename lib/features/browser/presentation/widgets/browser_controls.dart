import 'package:flutter/material.dart';

class BrowserControls extends StatelessWidget {
  const BrowserControls({
    required this.canGoBack,
    required this.isLoading,
    required this.isVideoPlaying,
    required this.title,
    required this.featuresEnabled,
    required this.pipEnabled,
    required this.onEnterPiP,
    required this.onBack,
    required this.onRefresh,
    required this.onAccount,
    super.key,
  });

  final bool canGoBack;
  final bool isLoading;
  final bool isVideoPlaying;
  final String title;
  final bool featuresEnabled;
  final bool pipEnabled;
  final VoidCallback onEnterPiP;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPremium = title == 'PREMIUM';

    return Material(
      color: Colors.white,
      child: SizedBox(
        height: 42,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 132),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isPremium
                      ? const Color(0xFFE62117)
                      : const Color(0xFF111111),
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Positioned.fill(
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: featuresEnabled && canGoBack ? onBack : null,
                    tooltip: 'Back',
                    color: const Color(0xFFE62117),
                    constraints: const BoxConstraints.tightFor(
                      width: 38,
                      height: 38,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: featuresEnabled ? onRefresh : null,
                    tooltip: 'Refresh',
                    color: const Color(0xFFE62117),
                    constraints: const BoxConstraints.tightFor(
                      width: 38,
                      height: 38,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  const Spacer(),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox.square(
                        dimension: 12,
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
                          ? const Color(0xFFE62117)
                          : colorScheme.outline,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: IconButton(
                      icon: Icon(
                        pipEnabled
                            ? Icons.picture_in_picture_alt
                            : Icons.picture_in_picture_alt_outlined,
                      ),
                      onPressed: featuresEnabled && pipEnabled
                          ? onEnterPiP
                          : null,
                      tooltip: 'PiP',
                      color: const Color(0xFFE62117),
                      constraints: const BoxConstraints.tightFor(
                        width: 38,
                        height: 38,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.account_circle_outlined),
                    onPressed: onAccount,
                    tooltip: 'Account',
                    color: const Color(0xFFE62117),
                    constraints: const BoxConstraints.tightFor(
                      width: 38,
                      height: 38,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
