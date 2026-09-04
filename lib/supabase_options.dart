class SupabaseOptions {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qbbcpmdtlfpnbslmueoc.supabase.co',
  );

  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_TaDEtocQyHxad46aj4cPGg_1DLEpMXv',
  );
}
