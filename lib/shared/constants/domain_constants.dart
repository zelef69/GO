class DomainConstants {
  const DomainConstants._();

  static const List<String> navigationAllowedHosts = <String>[
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'youtu.be',
  ];

  // Keep navigation strict but allow only hosts required for
  // in-app Google/YouTube authentication hand-off.
  static const List<String> navigationAuthAllowedHosts = <String>[
    'accounts.google.com',
    'accounts.youtube.com',
    'consent.youtube.com',
    'myaccount.google.com',
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
