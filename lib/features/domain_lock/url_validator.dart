class URLValidator {
  const URLValidator();

  static const Set<String> _resourceSafeSchemes = <String>{
    'about',
    'blob',
    'data',
    'javascript',
  };

  bool isNavigationSchemeAllowed(Uri uri) {
    return uri.scheme.toLowerCase() == 'https';
  }

  bool isRequestSchemeAllowed(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'https' || _resourceSafeSchemes.contains(scheme);
  }
}
