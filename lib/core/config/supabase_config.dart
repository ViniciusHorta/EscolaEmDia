abstract final class SupabaseConfig {
  // Public client configuration; no privileged server key belongs in this file.
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hhgxxvvreyhigxynrgmv.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_7cBwufZF1sDnn_tUEJm57A_i0pCVDCF',
  );
}
