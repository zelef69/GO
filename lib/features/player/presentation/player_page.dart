import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../../app/config/app_dependencies.dart';

class PlayerPageArgs {
  const PlayerPageArgs({
    required this.videoId,
    this.launchInBackground = false,
  });

  final String videoId;
  final bool launchInBackground;
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({required this.dependencies, required this.args, super.key});

  final AppDependencies dependencies;
  final PlayerPageArgs args;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final YoutubePlayerController _playerController;
  late final bool _pipEnabled;

  bool _isPlayerReady = false;
  bool _didAttemptBackgroundHandoff = false;
  bool _isRequestingPiP = false;
  bool _lastPlayingState = false;
  bool _lastFullscreenState = false;
  bool _isInPiPMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pipEnabled = widget.dependencies.settingsController.pipEnabled;

    _playerController = YoutubePlayerController(
      initialVideoId: widget.args.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        disableDragSeek: false,
        enableCaption: true,
      ),
    )..addListener(_onPlayerValueChanged);

    unawaited(widget.dependencies.pipChannel.setPiPEnabled(_pipEnabled));
    widget.dependencies.pipChannel.setMethodCallHandler(_onNativePiPEvent);
    unawaited(_sendVideoStateToNative(isPlaying: false, isFullscreen: false));

    if (widget.args.launchInBackground) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_attemptBackgroundPiPHandoff());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_pipEnabled) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_requestPiPFromPlayer());
      return;
    }

    if (state == AppLifecycleState.resumed && widget.args.launchInBackground) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (_isInPiPMode) {
          return;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  Future<dynamic> _onNativePiPEvent(MethodCall call) async {
    switch (call.method) {
      case 'onPiPAction':
        final args = call.arguments;
        final payload = args is Map
            ? Map<String, dynamic>.from(args)
            : const <String, dynamic>{};
        final action = payload['action']?.toString() ?? '';
        if (action == 'togglePlayPause') {
          if (_playerController.value.isPlaying) {
            _playerController.pause();
          } else {
            _playerController.play();
          }
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await _sendVideoStateToNative(
            isPlaying: _playerController.value.isPlaying,
            isFullscreen: _playerController.value.isFullScreen,
          );
        } else if (action == 'next') {
          final webViewController = _playerController.value.webViewController;
          if (webViewController != null) {
            await webViewController.evaluateJavascript(source: 'nextVideo();');
            await Future<void>.delayed(const Duration(milliseconds: 80));
            await _sendVideoStateToNative(
              isPlaying: true,
              isFullscreen: _playerController.value.isFullScreen,
            );
          }
        }
        _onPlayerValueChanged();
        return null;
      case 'onPiPModeChanged':
        final args = call.arguments;
        final payload = args is Map
            ? Map<String, dynamic>.from(args)
            : const <String, dynamic>{};
        _isInPiPMode = payload['isInPiPMode'] == true;
        if (_isInPiPMode) {
          _playerController.play();
          await _sendVideoStateToNative(isPlaying: true, isFullscreen: false);
        }
        return null;
      default:
        return null;
    }
  }

  Future<void> _sendVideoStateToNative({
    required bool isPlaying,
    required bool isFullscreen,
  }) async {
    await widget.dependencies.pipChannel.setVideoState(
      isPlaying: isPlaying,
      isFullscreen: isFullscreen,
      videoWidth: 16,
      videoHeight: 9,
    );
  }

  void _onPlayerValueChanged() {
    final value = _playerController.value;
    final isPlaying = value.isPlaying;
    final isFullscreen = value.isFullScreen;
    if (isPlaying == _lastPlayingState &&
        isFullscreen == _lastFullscreenState) {
      return;
    }

    _lastPlayingState = isPlaying;
    _lastFullscreenState = isFullscreen;
    unawaited(
      _sendVideoStateToNative(isPlaying: isPlaying, isFullscreen: isFullscreen),
    );
  }

  Future<void> _requestPiPFromPlayer() async {
    if (_isRequestingPiP) {
      return;
    }
    _isRequestingPiP = true;
    try {
      final isPlaying =
          _playerController.value.isPlaying ||
          _isPlayerReady ||
          widget.args.launchInBackground;
      await _sendVideoStateToNative(
        isPlaying: isPlaying,
        isFullscreen: _playerController.value.isFullScreen,
      );
      final entered = await widget.dependencies.pipChannel.enterPiPIfEligible();
      if (entered) {
        _playerController.play();
        await Future<void>.delayed(const Duration(milliseconds: 180));
        _playerController.play();
      }
    } finally {
      _isRequestingPiP = false;
    }
  }

  Future<void> _attemptBackgroundPiPHandoff() async {
    if (_didAttemptBackgroundHandoff || !_pipEnabled) {
      return;
    }
    _didAttemptBackgroundHandoff = true;
    if (!mounted) {
      return;
    }
    await _requestPiPFromPlayer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.dependencies.pipChannel.setMethodCallHandler(null);
    _playerController.removeListener(_onPlayerValueChanged);
    _playerController.pause();
    _playerController.dispose();
    unawaited(_sendVideoStateToNative(isPlaying: false, isFullscreen: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      onExitFullScreen: () {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      },
      player: YoutubePlayer(
        controller: _playerController,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Theme.of(context).colorScheme.primary,
        onReady: () {
          _isPlayerReady = true;
          _playerController.play();
          _onPlayerValueChanged();
        },
      ),
      builder: (context, player) {
        if (widget.args.launchInBackground) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: AspectRatio(aspectRatio: 16 / 9, child: player),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Player')),
          body: Center(
            child: AspectRatio(aspectRatio: 16 / 9, child: player),
          ),
        );
      },
    );
  }
}
