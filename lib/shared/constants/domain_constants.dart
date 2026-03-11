class DomainConstants {
  const DomainConstants._();

  static const List<String> navigationAllowedHosts = <String>[
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'youtu.be',
  ];

  static const List<String> requestAllowedHostPatterns = <String>[
    'youtube.com',
    '*.youtube.com',
    'youtu.be',
    '*.youtu.be',
    '*.youtube-nocookie.com',
    '*.googlevideo.com',
    '*.ytimg.com',
    'youtubei.googleapis.com',
    '*.googleapis.com',
    '*.googleusercontent.com',
    '*.gstatic.com',
    '*.google.com',
    'accounts.google.com',
    '*.ggpht.com',
    '*.gvt1.com',
  ];
}
