import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase login session in secure storage instead of plain SharedPreferences.
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const sessionKey = 'sb_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _storage.read(key: sessionKey)) != null;

  /// The whole persisted session JSON (what supabase_flutter expects back).
  @override
  Future<String?> accessToken() => _storage.read(key: sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) => _storage.write(key: sessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: sessionKey);
}
