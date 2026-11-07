#!/usr/bin/env bash
# Ambiente de staging da feature de assinaturas (projeto escolaemdia_staging).
# Todos os comandos usam a ref do staging de forma explícita — nunca a produção.
set -euo pipefail

STAGING_REF="ivtnjputmlsvbuakrzdw"
STAGING_URL="https://${STAGING_REF}.supabase.co"
STAGING_PUBLISHABLE_KEY="sb_publishable_NWfWgS9UZbh25mplti0j0A_807dbcMb"

cd "$(dirname "$0")/.."

usage() {
  cat <<EOF
Uso: tools/staging.sh <comando>

  app [args]        Corre o app Flutter (web, porta 8080) contra o staging
  device [id]       Corre o app num telemóvel/emulador ligado contra o staging
                    (sem id usa o único dispositivo ligado; ver: flutter devices)
  db:dry            Mostra as migrations pendentes no staging
  db:push           Aplica as migrations pendentes no staging
  fn:deploy [nome]  Publica as edge functions (todas ou só uma) no staging
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
  db:dry)    supabase db push --remote="$STAGING_REF" --dry-run ;;
  db:push)   supabase db push --remote="$STAGING_REF" ;;
  fn:deploy) supabase functions deploy "$@" --remote="$STAGING_REF" ;;
  sql)       supabase db query --remote="$STAGING_REF" "$1" ;;
  test)      supabase db query --remote="$STAGING_REF" --file "$1" ;;
  *)         usage; exit 1 ;;
esac
