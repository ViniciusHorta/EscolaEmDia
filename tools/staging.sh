#!/usr/bin/env bash
# Ambiente de staging (projeto Supabase Cloud escolaemdia_staging).
# Todos os comandos usam a ref do staging de forma explícita — nunca a produção.
# Para testar no staging antes de publicar em produção (hhgxxvvreyhigxynrgmv).
set -euo pipefail

STAGING_REF="ivtnjputmlsvbuakrzdw"
STAGING_URL="https://${STAGING_REF}.supabase.co"
# Chave pública (publishable) — pode estar no git. Segredos (Stripe, etc.) vão para
# supabase/functions/.env.staging, que está fora do git.
STAGING_PUBLISHABLE_KEY="sb_publishable_NWfWgS9UZbh25mplti0j0A_807dbcMb"

cd "$(dirname "$0")/.."

usage() {
  cat <<EOF
Uso: tools/staging.sh <comando>

  app [args]        Corre o app Flutter (web, porta 8080) contra o staging
  device [id]       Corre o app num telemóvel/emulador ligado contra o staging
                    (sem id usa o único dispositivo ligado; ver: flutter devices)
  bundle            Gera o .aab de release (Google Play, teste interno) apontado ao staging
  ipa               Gera o .ipa de release (App Store, TestFlight) apontado ao staging
                    (requer Xcode com a conta Apple Developer e assinatura automática)
  db:dry            Mostra as migrations pendentes no staging
  db:push           Aplica as migrations pendentes no staging
  fn:deploy [nome]  Publica as edge functions (todas ou só uma) no staging
  secrets           Envia supabase/functions/.env.staging (fora do git) para os secrets do staging
  sql "<query>"     Executa SQL no staging
  test <ficheiro>   Corre um teste SQL (transação com ROLLBACK) no staging
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  app)
    flutter run -d chrome --web-port 8080 \
      --dart-define=SUPABASE_URL="$STAGING_URL" \
      --dart-define=SUPABASE_PUBLISHABLE_KEY="$STAGING_PUBLISHABLE_KEY" "$@"
    ;;
  device)
    flutter run ${1:+-d "$1"} \
      --dart-define=SUPABASE_URL="$STAGING_URL" \
      --dart-define=SUPABASE_PUBLISHABLE_KEY="$STAGING_PUBLISHABLE_KEY" "${@:2}"
    ;;
  bundle)
    [ -f android/key.properties ] || { echo "Falta android/key.properties (chave de upload). O Google Play recusa builds de debug."; exit 1; }
    flutter build appbundle --release \
      --dart-define=SUPABASE_URL="$STAGING_URL" \
      --dart-define=SUPABASE_PUBLISHABLE_KEY="$STAGING_PUBLISHABLE_KEY" "$@"
    echo "→ build/app/outputs/bundle/release/app-release.aab"
    ;;
  ipa)
    flutter build ipa --release \
      --dart-define=SUPABASE_URL="$STAGING_URL" \
      --dart-define=SUPABASE_PUBLISHABLE_KEY="$STAGING_PUBLISHABLE_KEY" "$@"
    echo "→ build/ios/ipa/ (enviar para o TestFlight com a app Transporter ou: xcrun altool / Xcode → Organizer)"
    ;;
  db:dry)    supabase db push --remote="$STAGING_REF" --dry-run ;;
  db:push)   supabase db push --remote="$STAGING_REF" ;;
  fn:deploy) supabase functions deploy "$@" --remote="$STAGING_REF" ;;
  secrets)
    [ -f supabase/functions/.env.staging ] || { echo "Falta supabase/functions/.env.staging"; exit 1; }
    supabase secrets set --env-file supabase/functions/.env.staging --remote="$STAGING_REF" ;;
  sql)       supabase db query --remote="$STAGING_REF" "$1" ;;
  test)      supabase db query --remote="$STAGING_REF" --file "$1" ;;
  *)         usage; exit 1 ;;
esac
