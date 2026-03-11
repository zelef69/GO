import 'domain_policy_service.dart';

enum NavigationBlockReason {
  invalidUrl,
  unsafeScheme,
  disallowedHost,
}

class NavigationCheckResult {
  const NavigationCheckResult._({
    required this.isAllowed,
    required this.reason,
  });

  const NavigationCheckResult.allowed()
      : this._(isAllowed: true, reason: null);

  const NavigationCheckResult.blocked(NavigationBlockReason reason)
      : this._(isAllowed: false, reason: reason);

  final bool isAllowed;
  final NavigationBlockReason? reason;
}

class NavigationInterceptor {
  NavigationInterceptor({required DomainPolicyService domainPolicyService})
      : _domainPolicyService = domainPolicyService;

  final DomainPolicyService _domainPolicyService;

  NavigationCheckResult evaluate(Uri? uri) {
    if (uri == null) {
      return const NavigationCheckResult.blocked(
        NavigationBlockReason.invalidUrl,
      );
    }

    if (!_domainPolicyService.urlValidator.isNavigationSchemeAllowed(uri)) {
      return const NavigationCheckResult.blocked(
        NavigationBlockReason.unsafeScheme,
      );
    }

    if (!_domainPolicyService.isNavigationHostAllowed(uri.host)) {
      return const NavigationCheckResult.blocked(
        NavigationBlockReason.disallowedHost,
      );
    }

    return const NavigationCheckResult.allowed();
  }
}
