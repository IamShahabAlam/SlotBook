import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_build_config.dart';
import '../../utils/custom_functions/logger.dart';

/// Starts Supabase for this build's backend. Without one (plain `flutter run`, tests) the app runs offline-only for now.
abstract final class SupabaseSetup {
  static bool _started = false;

  /// Whether Supabase was started; `Supabase.instance` is only usable when true.
  static bool get isStarted => _started;

  static Future<bool> start(BackendConfig? backend, LocalStorage sessionStorage) async {
    if (backend == null) {
      Logger.logs('No backend configured (pass --dart-define-from-file=config/<env>.json); Supabase not started.');
      return false;
    }
    await Supabase.initialize(
      url: backend.url.toString(),
      publishableKey: backend.anonKey, // a legacy anon key or a new publishable key; both are public
      // Sign-in is an emailed code, not a link, so no deep-link session detection.
      authOptions: FlutterAuthClientOptions(localStorage: sessionStorage, detectSessionInUri: false),
    );
    Logger.logs('Supabase started (${backend.env}: ${backend.url.host}).');
    return _started = true;
  }
}
