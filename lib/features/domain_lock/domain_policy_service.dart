import '../../shared/constants/domain_constants.dart';
import '../../shared/utils/host_matcher.dart';
import 'url_validator.dart';

class DomainPolicyService {
  DomainPolicyService({
    URLValidator? urlValidator,
    List<String>? navigationAllowedHosts,
    List<String>? requestAllowedHostPatterns,
  }) : urlValidator = urlValidator ?? const URLValidator(),
       _navigationAllowedHosts =
           navigationAllowedHosts ?? DomainConstants.navigationAllowedHosts,
       _requestAllowedHostPatterns =
           requestAllowedHostPatterns ??
           DomainConstants.requestAllowedHostPatterns;

  final URLValidator urlValidator;
  final List<String> _navigationAllowedHosts;
  final List<String> _requestAllowedHostPatterns;
  static const List<String> _requestDeniedAdHostPatterns = <String>[
    'doubleclick.net',
    '*.doubleclick.net',
    'googlesyndication.com',
    '*.googlesyndication.com',
    'googleadservices.com',
    '*.googleadservices.com',
    'adservice.google.com',
    '*.adservice.google.com',
    'pagead2.googlesyndication.com',
    'pubads.g.doubleclick.net',
    'securepubads.g.doubleclick.net',
  ];

  bool isNavigationHostAllowed(String host) {
    return HostMatcher.matches(host, _navigationAllowedHosts);
  }

  bool isNavigationAllowed(Uri uri) {
    return urlValidator.isNavigationSchemeAllowed(uri) &&
        isNavigationHostAllowed(uri.host);
  }

  bool isRequestAllowed(Uri uri) {
    if (!urlValidator.isRequestSchemeAllowed(uri)) {
      return false;
    }

    if (uri.scheme.toLowerCase() != 'https') {
      return true;
    }

    if (HostMatcher.matches(uri.host, _requestDeniedAdHostPatterns)) {
      return false;
    }

    return HostMatcher.matches(uri.host, _requestAllowedHostPatterns);
  }
}
