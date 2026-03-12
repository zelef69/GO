import 'security_service.dart';

/// Integration point for server-gated trust decisions.
///
/// The client can collect risk context + signed nonce, but the final
/// authorization decision must be done on backend for sensitive features.
class ServerTrustService {
  ServerTrustService({required SecurityService securityService})
    : _securityService = securityService;

  final SecurityService _securityService;

  Future<Map<String, dynamic>> buildSignedRequestContext({
    required String nonce,
    required String action,
  }) async {
    await _securityService.checkpointSensitiveAction('server_trust:$action');
    final trustSignal = await _securityService.buildTrustSignal(
      nonce: nonce,
      context: action,
    );
    return <String, dynamic>{
      'action': action,
      'trustSignal': trustSignal,
      // TODO(security-backend): Verify signature, key continuity, and risk
      // score server-side before allowing premium/license-sensitive operations.
    };
  }
}
