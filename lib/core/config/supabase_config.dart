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

/// IDs públicos do login Google nativo (Android/iOS). O token pedido à Google vem "endereçado" ao
/// cliente Web configurado no Supabase Auth de cada ambiente (produção por omissão; o staging
/// é passado por tools/staging.sh).
abstract final class GoogleSignInConfig {
  static const webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '958174914246-b6bu0s94ksgl23e1akv6krlgdg9huf5t.apps.googleusercontent.com',
  );
  static const iosClientId = '958174914246-a58d0iv4v40ct453upje2jao82n2hga9.apps.googleusercontent.com';
}
