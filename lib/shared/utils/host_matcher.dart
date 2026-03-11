class HostMatcher {
  const HostMatcher._();

  static bool matches(String host, List<String> patterns) {
    final normalizedHost = host.toLowerCase();
    for (final pattern in patterns) {
      final candidate = pattern.trim().toLowerCase();
      if (candidate.isEmpty) {
        continue;
      }
      if (candidate.startsWith('*.')) {
        final suffix = candidate.substring(2);
        if (normalizedHost == suffix || normalizedHost.endsWith('.$suffix')) {
          return true;
        }
        continue;
      }
      if (normalizedHost == candidate) {
        return true;
      }
    }
    return false;
  }
}
