import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arenabook/app/config/app_build_config.dart';
import 'package:arenabook/app/service/getx_service/secure_storage_service.dart';
import 'package:arenabook/app/service/supabase/secure_session_storage.dart';
import 'package:arenabook/app/service/supabase/supabase_setup.dart';

/// A legacy Supabase key: an (unsigned, for tests) JWT carrying [role].
String jwtKey(String role) {
  String part(Map<String, Object> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'iss': 'supabase', 'ref': 'abc', 'role': role})}.signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = 'https://abcdefghij.supabase.co';
  BackendConfig? resolve({String env = 'dev', String url = '', String key = ''}) => BackendConfig.resolve(env: env, url: url, anonKey: key);
  final throwsConfig = throwsA(isA<BackendConfigException>());

  group('BackendConfig.resolve', () {
    test('no values in dev = no backend (plain flutter run, tests)', () {
      expect(resolve(), isNull);
      expect(AppBuildConfig.backend, isNull);
      expect(AppBuildConfig.clientCode, 'demo');
    });

    test('a valid project', () {
      final backend = resolve(url: ' $url ', key: ' sb_publishable_abc ')!;
      expect(backend.url.host, 'abcdefghij.supabase.co');
      expect(backend.anonKey, 'sb_publishable_abc');
      expect(resolve(env: 'prod', url: url, key: jwtKey('anon'))!.env, 'prod');
    });

    test('a prod build must have a backend', () => expect(() => resolve(env: 'prod'), throwsConfig));

    test('unknown APP_ENV', () => expect(() => resolve(env: 'staging'), throwsConfig));

    test('half-filled, placeholder or non-https values fail at startup', () {
      expect(() => resolve(url: url), throwsConfig);
      expect(() => resolve(key: 'sb_publishable_abc'), throwsConfig);
      expect(() => resolve(url: 'https://<ref>.supabase.co', key: '<anon-or-publishable-key>'), throwsConfig);
      expect(() => resolve(url: 'http://abcdefghij.supabase.co', key: 'sb_publishable_abc'), throwsConfig);
      expect(() => resolve(url: url, key: '<anon-or-publishable-key>'), throwsConfig);
    });

    test('a secret (service) key is refused', () {
      expect(() => resolve(url: url, key: 'sb_secret_abc'), throwsConfig);
      expect(() => resolve(url: url, key: jwtKey('service_role')), throwsConfig);
    });

    test('config/example.json has the three keys and means "no backend" when copied as is', () {
      final json = (jsonDecode(File('config/example.json').readAsStringSync()) as Map).cast<String, String>();
      expect(json.keys, unorderedEquals(['APP_ENV', 'SUPABASE_URL', 'SUPABASE_ANON_KEY']));
      expect(BackendConfig.resolve(env: json['APP_ENV']!, url: json['SUPABASE_URL']!, anonKey: json['SUPABASE_ANON_KEY']!), isNull);
    });
  });

  group('secure storage', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));
    const storage = FlutterSecureStorage();

    test('the cache key is created once and then reused', () async {
      final (first, firstIsNew) = await SecureStorageService.loadCacheKey(storage);
      final (second, secondIsNew) = await SecureStorageService.loadCacheKey(storage);
      expect(first, hasLength(32));
      expect((firstIsNew, secondIsNew), (true, false));
      expect(second, first);
    });

    test('a damaged cache key is replaced (and reported as new, so old caches get cleared)', () async {
      for (final damaged in [
        'not base64!',
        base64Encode([1, 2, 3]),
      ]) {
        FlutterSecureStorage.setMockInitialValues({SecureStorageService.cacheKeyName: damaged});
        final (key, isNew) = await SecureStorageService.loadCacheKey(storage);
        expect((key.length, isNew), (32, true), reason: damaged);
        expect(await storage.read(key: SecureStorageService.cacheKeyName), base64Encode(key));
      }
    });

    test('the login session round-trips through secure storage', () async {
      const sessions = SecureSessionStorage(storage);
      expect(await sessions.hasAccessToken(), isFalse);
      await sessions.persistSession('{"access_token":"t"}');
      expect(await sessions.hasAccessToken(), isTrue);
      expect(await sessions.accessToken(), '{"access_token":"t"}');
      await sessions.removePersistedSession();
      expect(await sessions.accessToken(), isNull);
    });

    test('without a backend, Supabase is not started', () async {
      expect(await SupabaseSetup.start(null, const SecureSessionStorage(storage)), isFalse);
      expect(SupabaseSetup.isStarted, isFalse);
    });
  });
}
