class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yktyobprlradqtvmqfki.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_foYtDGPKyHV_wpdgjPcsjg_0x25jZMm',
  );

  static bool get isConfigured =>
      url.startsWith('https://') && publishableKey.startsWith('sb_');
}
