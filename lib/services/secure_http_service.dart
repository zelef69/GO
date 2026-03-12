import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'native_secrets_service.dart';
import 'security_service.dart';

/// Centralized secure HTTP factory.
///
/// Security properties:
/// - Uses a trusted system root store (normal TLS chain validation).
/// - Applies SHA-256 certificate pin verification (fail closed).
/// - Runs a security checkpoint before sensitive requests.
/// - Supports pin rotation by accepting multiple backup pins.
class SecureHttpService {
  SecureHttpService({
    required NativeSecretsService nativeSecretsService,
    required SecurityService securityService,
  }) : _nativeSecretsService = nativeSecretsService,
       _securityService = securityService;

  final NativeSecretsService _nativeSecretsService;
  final SecurityService _securityService;

  Future<Dio> createPinnedClient({
    required String baseUrl,
    Duration connectTimeout = const Duration(seconds: 12),
    Duration receiveTimeout = const Duration(seconds: 15),
  }) async {
    await _securityService.checkpointSensitiveAction('http_client_create');
    final nativeSecrets = await _nativeSecretsService.loadNativeSecrets();
    final pinSet = nativeSecrets.certificatePinsSha256
        .map((e) => e.toUpperCase())
        .toSet();

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
      ),
    );

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient(
          context: SecurityContext(withTrustedRoots: true),
        );
        // Always reject certs that fail platform trust validation.
        client.badCertificateCallback = (certificate, host, port) => false;
        return client;
      },
      // Additional certificate pinning on top of trust chain validation.
      validateCertificate: (certificate, host, port) {
        if (certificate == null || pinSet.isEmpty) {
          return false;
        }
        final certSha256 = sha256
            .convert(certificate.der)
            .toString()
            .toUpperCase();
        return pinSet.contains(certSha256);
      },
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final checkpointName =
              'http_request:${options.method}:${options.uri.host}';
          await _securityService.checkpointSensitiveAction(checkpointName);
          handler.next(options);
        },
      ),
    );

    return dio;
  }
}
