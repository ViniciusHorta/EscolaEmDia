#!/usr/bin/env bash
# Stack Supabase de desenvolvimento no servidor de containers "vaio" (via VPN).
# Funciona como o staging: BD, migrations, SQL e app falam diretamente com o
# servidor a partir do Mac. O vaio guarda só o que a cloud guardaria por nós:
# config.toml (definições do projeto), o código publicado das Edge Functions e
# os secrets — enviados com config:deploy, fn:deploy e secrets.
set -euo pipefail

HOST="${SUPABASE_DEV_HOST:-vaio}"            # alias SSH (só para deploy/start/stop)
IP="${SUPABASE_DEV_IP:-100.93.164.71}"       # IP do vaio na VPN
REMOTE_DIR="escola-em-dia-dev"               # no vaio: ~/escola-em-dia-dev/supabase/
SB='~/.local/bin/supabase'

API_URL="http://$IP:55321"
DB_URL="postgresql://postgres:postgres@$IP:55322/postgres?sslmode=disable"

cd "$(dirname "$0")/.."

usage() {
  cat <<EOF
Uso: tools/local.sh <comando>

  app [args]        Corre o app Flutter (web, porta 8080) contra o vaio
  device [id]       Corre o app num telemóvel/emulador contra o vaio (precisa da VPN)
  db:dry            Mostra as migrations pendentes no vaio
  db:push           Aplica as migrations pendentes no vaio
  db:reset          Recria a BD do vaio a partir das migrations do Mac
  fn:deploy [nome]  Publica as Edge Functions (todas ou só uma) no vaio
  secrets           Envia supabase/functions/.env (fora do git) para o vaio
  sql "<query>"     Executa SQL no vaio
  test <ficheiro>   Corre um teste SQL no vaio
  status            URLs e chaves da stack
  config:deploy     Envia supabase/config.toml para o vaio e reinicia a stack
  start | stop      Liga / desliga os containers no vaio (stop mantém os dados)

Studio: http://$IP:55323 · Mailpit: http://$IP:55324 · API: $API_URL
EOF
}

on_host() { ssh "$HOST" "cd $REMOTE_DIR && $*"; }

# config.toml do repositório com os URLs públicos apontados ao IP da VPN.
deploy_config() {
  ssh "$HOST" "mkdir -p $REMOTE_DIR/supabase/functions"
  sed -e "s|^api_url = \"http://127.0.0.1\"|api_url = \"http://$IP\"|" \
      -e "s|^\[api\]$|[api]\nexternal_url = \"$API_URL\"|" \
      supabase/config.toml | ssh "$HOST" "cat > $REMOTE_DIR/supabase/config.toml"
}

publishable_key() {
  on_host "$SB status -o env" 2>/dev/null \
    | sed -n 's/^PUBLISHABLE_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p'
}

cmd="${1:-}"; shift || true
case "$cmd" in
  app)
    flutter run -d chrome --web-port 8080 \
      --dart-define=SUPABASE_URL="$API_URL" \
      --dart-define=SUPABASE_PUBLISHABLE_KEY="$(publishable_key)" "$@"
    ;;
  device)
    flutter run ${1:+-d "$1"} \
      --dart-define=SUPABASE_URL="$API_URL" \
      --dart-define=SUPABASE_PUBLISHABLE_KEY="$(publishable_key)" "${@:2}"
    ;;
  db:dry)   supabase db push --remote="$DB_URL" --dry-run ;;
  db:push)  supabase db push --remote="$DB_URL" ;;
  db:reset) supabase db reset --remote="$DB_URL" ;;
  fn:deploy)
    # Sem --delete no _shared e na publicação completa: o vaio é partilhado por várias
    # branches, e apagar ficheiros que não existem nesta (ex.: módulos de outra feature)
    # partiria as funções publicadas a partir dessas branches.
    if [ $# -gt 0 ]; then
      for fn in "$@"; do
        rsync -az --delete "supabase/functions/$fn/" "$HOST:$REMOTE_DIR/supabase/functions/$fn/"
      done
      rsync -az supabase/functions/_shared/ "$HOST:$REMOTE_DIR/supabase/functions/_shared/"
    else
      rsync -az --exclude '.env*' supabase/functions/ "$HOST:$REMOTE_DIR/supabase/functions/"
    fi
    echo "Functions publicadas no vaio (o Edge Runtime recarrega no próximo pedido)."
    ;;
  secrets)
    [ -f supabase/functions/.env ] || { echo "Falta supabase/functions/.env"; exit 1; }
    scp -q supabase/functions/.env "$HOST:$REMOTE_DIR/supabase/functions/.env"
    echo "Secrets enviados. Aplicam-se após: tools/local.sh stop && tools/local.sh start"
    ;;
  sql)      supabase db query --remote="$DB_URL" "$1" ;;
  test)     supabase db query --remote="$DB_URL" --file "$1" ;;
  status)   on_host "$SB status" ;;
  config:deploy) deploy_config; on_host "$SB stop && $SB start" ;;
  start)    on_host "$SB start" ;;
  stop)     on_host "$SB stop" ;;
  *)        usage; exit 1 ;;
esac
