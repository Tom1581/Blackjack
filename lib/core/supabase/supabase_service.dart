import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// The live Supabase client. Only read this behind [AppSupabase.isReady] —
/// it throws when the backend never came up.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

class AppSupabase {
  const AppSupabase._();

  static bool _ready = false;
  static Object? _error;

  /// Whether online features can run. When false, single-player still works
  /// normally — nothing offline depends on the backend.
  static bool get isReady => _ready;

  /// Why start-up failed, so the online screen can say something useful.
  static Object? get lastError => _error;

  /// The actual connect step, swappable so the failure paths can be tested
  /// without a live backend.
  @visibleForTesting
  static Future<void> Function() initializer = _connect;

  static Future<void> _connect() async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase URL or publishable key is not configured.');
    }
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

  /// Best-effort connect for app start-up. **Never throws and never hangs.**
  ///
  /// This used to be a bare `await` in `main()` ahead of `runApp()`, so a bad
  /// key, a blocked host, or a dead network took the app down before it drew
  /// a single frame — an install that can never register a first open. The
  /// app must always reach its lobby; only online play is allowed to fail.
  static Future<bool> tryInitialize({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_ready) return true;
    try {
      await initializer().timeout(timeout);
      _ready = true;
      _error = null;
    } catch (error) {
      _ready = false;
      _error = error;
      debugPrint('Supabase unavailable — online play is disabled: $error');
    }
    return _ready;
  }

  @visibleForTesting
  static void resetForTest() {
    _ready = false;
    _error = null;
    initializer = _connect;
  }
}
