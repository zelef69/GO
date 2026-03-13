const Set<String> _compoundTlds = <String>{
  'co.uk',
  'org.uk',
  'gov.uk',
  'ac.uk',
  'com.au',
  'net.au',
  'co.jp',
  'com.br',
};

const Set<String> _genericHostTokens = <String>{
  'com',
  'net',
  'org',
  'co',
  'io',
  'uk',
  'www',
};

String registrableDomainFromHost(String host) {
  final normalized = host.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }
  final labels = normalized
      .split('.')
      .where((label) => label.isNotEmpty)
      .toList(growable: false);
  if (labels.length <= 2) {
    return normalized;
  }
  final tailTwo = '${labels[labels.length - 2]}.${labels[labels.length - 1]}';
  final tailThree = labels.length >= 3
      ? '${labels[labels.length - 3]}.$tailTwo'
      : tailTwo;
  if (_compoundTlds.contains(tailTwo) && labels.length >= 3) {
    return tailThree;
  }
  return tailTwo;
}

Set<String> tokenizeHostname(String host) {
  final normalized = host.trim().toLowerCase();
  if (normalized.isEmpty) {
    return const <String>{};
  }
  final tokens = <String>{normalized};
  final labels = normalized
      .split('.')
      .where((label) => label.isNotEmpty)
      .toList(growable: false);
  for (var index = 0; index < labels.length; index += 1) {
    final label = labels[index];
    if (!_genericHostTokens.contains(label)) {
      tokens.add(label);
    }
    final suffix = labels.sublist(index).join('.');
    if (suffix.isNotEmpty && !_genericHostTokens.contains(suffix)) {
      tokens.add(suffix);
    }
  }
  final domain = registrableDomainFromHost(normalized);
  if (domain.isNotEmpty) {
    tokens.add(domain);
  }
  return tokens;
}

Set<String> tokenizePath(String path) {
  final normalized = path.trim().toLowerCase();
  if (normalized.isEmpty) {
    return const <String>{};
  }
  final rawParts = normalized.split(RegExp(r'[^a-z0-9]+'));
  return rawParts.where((part) => part.isNotEmpty).toSet();
}

Set<String> tokenizeUrl(Uri uri) {
  final tokens = <String>{};
  tokens.addAll(tokenizeHostname(uri.host));
  tokens.addAll(tokenizePath(uri.path));
  tokens.addAll(tokenizePath(uri.query));
  tokens.addAll(tokenizePath(uri.fragment));
  return tokens;
}
