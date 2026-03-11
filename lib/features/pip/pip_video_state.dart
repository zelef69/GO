class PiPVideoState {
  const PiPVideoState({
    required this.isPlaying,
    required this.isFullscreen,
    required this.videoWidth,
    required this.videoHeight,
    required this.videoRectLeft,
    required this.videoRectTop,
    required this.videoRectRight,
    required this.videoRectBottom,
    required this.title,
    required this.author,
    required this.durationMs,
    required this.positionMs,
    required this.hasNext,
  });

  factory PiPVideoState.empty() {
    return const PiPVideoState(
      isPlaying: false,
      isFullscreen: false,
      videoWidth: 0,
      videoHeight: 0,
      videoRectLeft: 0,
      videoRectTop: 0,
      videoRectRight: 0,
      videoRectBottom: 0,
      title: '',
      author: '',
      durationMs: 0,
      positionMs: 0,
      hasNext: false,
    );
  }

  final bool isPlaying;
  final bool isFullscreen;
  final int videoWidth;
  final int videoHeight;
  final int videoRectLeft;
  final int videoRectTop;
  final int videoRectRight;
  final int videoRectBottom;
  final String title;
  final String author;
  final int durationMs;
  final int positionMs;
  final bool hasNext;

  PiPVideoState copyWith({
    bool? isPlaying,
    bool? isFullscreen,
    int? videoWidth,
    int? videoHeight,
    int? videoRectLeft,
    int? videoRectTop,
    int? videoRectRight,
    int? videoRectBottom,
    String? title,
    String? author,
    int? durationMs,
    int? positionMs,
    bool? hasNext,
  }) {
    return PiPVideoState(
      isPlaying: isPlaying ?? this.isPlaying,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      videoRectLeft: videoRectLeft ?? this.videoRectLeft,
      videoRectTop: videoRectTop ?? this.videoRectTop,
      videoRectRight: videoRectRight ?? this.videoRectRight,
      videoRectBottom: videoRectBottom ?? this.videoRectBottom,
      title: title ?? this.title,
      author: author ?? this.author,
      durationMs: durationMs ?? this.durationMs,
      positionMs: positionMs ?? this.positionMs,
      hasNext: hasNext ?? this.hasNext,
    );
  }

  Map<String, dynamic> toChannelArguments() {
    return <String, dynamic>{
      'isPlaying': isPlaying,
      'isFullscreen': isFullscreen,
      'videoWidth': videoWidth,
      'videoHeight': videoHeight,
      'videoRectLeft': videoRectLeft,
      'videoRectTop': videoRectTop,
      'videoRectRight': videoRectRight,
      'videoRectBottom': videoRectBottom,
      'title': title,
      'author': author,
      'durationMs': durationMs,
      'positionMs': positionMs,
      'hasNext': hasNext,
    };
  }
}
