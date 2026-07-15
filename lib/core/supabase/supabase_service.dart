import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

class AppSupabase {
  const AppSupabase._();

  static Future<void> initialize() async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase URL or publishable key is not configured.');
    }

    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }
}
