import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalSessionStore {
  LocalSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _keyForUid(String uid) => 'go_play_session_id_$uid';

  Future<String?> readSessionId(String uid) {
    return _storage.read(key: _keyForUid(uid));
  }

  Future<void> writeSessionId(String uid, String sessionId) {
    return _storage.write(key: _keyForUid(uid), value: sessionId);
  }

  Future<void> clearSessionId(String uid) {
    return _storage.delete(key: _keyForUid(uid));
  }
}
