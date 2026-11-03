import 'dart:convert';

import 'package:flutter/services.dart' show appFlavor;

/// Build-time settings: the client (flavor) and the backend from `--dart-define-from-file=config/<env>.json`.
abstract final class AppBuildConfig {
  /// The client this build is for; the flavor name is the client's `client_code` in the database.
  static String get clientCode => appFlavor ?? 'demo';

  static const env = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// This build's Supabase project, or null when none is configured (plain `flutter run`, tests). Throws on a bad config.
  static final backend = BackendConfig.resolve(env: env, url: supabaseUrl, anonKey: supabaseAnonKey);
}

/// A Supabase project the app talks to. Only the public anon/publishable key ever belongs in the app.
class BackendConfig {
  const BackendConfig({required this.env, required this.url, required this.anonKey});

  final String env; // 'dev' or 'prod'
  final Uri url;
  final String anonKey;

  static const envs = {'dev', 'prod'};

  /// Checks the build's values so a misconfigured build fails at startup instead of misbehaving later.
  static BackendConfig? resolve({required String env, required String url, required String anonKey}) {
    url = url.trim();
    anonKey = anonKey.trim();
    if (!envs.contains(env)) throw BackendConfigException('APP_ENV must be dev or prod, not "$env".');
    if (url.isEmpty && anonKey.isEmpty) {
      if (env == 'prod') throw const BackendConfigException('A prod build needs SUPABASE_URL and SUPABASE_ANON_KEY.');
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || url.contains('<')) {
      throw const BackendConfigException('SUPABASE_URL must be the project\'s https URL.');
    }
    if (anonKey.isEmpty || anonKey.contains('<')) throw const BackendConfigException('SUPABASE_ANON_KEY is missing.');
    if (_isSecretKey(anonKey)) throw const BackendConfigException('SUPABASE_ANON_KEY is a secret (service) key. Never ship it in the app.');
    return BackendConfig(env: env, url: uri, anonKey: anonKey);
  }

  /// New-style secret keys, or a legacy JWT key whose role is service_role.
  static bool _isSecretKey(String key) {
    if (key.startsWith('sb_secret_')) return true;
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return payload is Map && payload['role'] == 'service_role';
    } on FormatException {
      return false;
    }
  }
}

class BackendConfigException implements Exception {
  const BackendConfigException(this.message);

  final String message;

  @override
  String toString() => 'BackendConfigException: $message';
}
