#!/usr/bin/env bash
# Envia o .aab para uma faixa de teste do Google Play (por omissão: teste interno) pela API.
# Credenciais: GOOGLE_PLAY_SERVICE_ACCOUNT (JSON em base64) e PLAY_PACKAGE_NAME do ficheiro
# supabase/functions/.env.staging (fora do git). A conta de serviço precisa da permissão
# «Lançar apps para faixas de teste» no Play Console.
#   tools/play-upload.sh [faixa] [ficheiro.aab]
set -euo pipefail
cd "$(dirname "$0")/.."

TRACK="${1:-internal}"
AAB="${2:-build/app/outputs/bundle/release/app-release.aab}"
ENV_FILE="supabase/functions/.env.staging"
[ -f "$AAB" ] || { echo "Falta $AAB (gera com: tools/staging.sh bundle)"; exit 1; }
[ -f "$ENV_FILE" ] || { echo "Falta $ENV_FILE"; exit 1; }
set -a; . "$ENV_FILE"; set +a
[ -n "${GOOGLE_PLAY_SERVICE_ACCOUNT:-}" ] && [ -n "${PLAY_PACKAGE_NAME:-}" ] || { echo "Faltam credenciais do Google Play em $ENV_FILE"; exit 1; }

VERSION_NAME=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
NAME="${VERSION_NAME%%+*} (${VERSION_NAME##*+})"

# --- Token OAuth da conta de serviço (JWT RS256 assinado com openssl) ---
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; chmod 700 "$TMP"
echo "$GOOGLE_PLAY_SERVICE_ACCOUNT" | base64 -d > "$TMP/sa.json"
python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["private_key"], end="")' "$TMP/sa.json" > "$TMP/k.pem"
EMAIL=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["client_email"])' "$TMP/sa.json")
b64u() { base64 | tr -d '\n=' | tr '+/' '-_'; }
NOW=$(date +%s)
H=$(printf '{"alg":"RS256","typ":"JWT"}' | b64u)
C=$(printf '{"iss":"%s","scope":"https://www.googleapis.com/auth/androidpublisher","aud":"https://oauth2.googleapis.com/token","iat":%d,"exp":%d}' "$EMAIL" "$NOW" $((NOW + 1800)) | b64u)
S=$(printf '%s.%s' "$H" "$C" | openssl dgst -sha256 -sign "$TMP/k.pem" | b64u)
TOKEN=$(curl -s https://oauth2.googleapis.com/token -d grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer -d assertion="$H.$C.$S" \
  | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))')
[ -n "$TOKEN" ] || { echo "Não foi possível autenticar a conta de serviço."; exit 1; }

API="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PLAY_PACKAGE_NAME"
UPLOAD="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$PLAY_PACKAGE_NAME"
call() { # método url [corpo]  → imprime a resposta; falha com a mensagem da Google
  local out code
  out=$(curl -s -w '\n%{http_code}' -X "$1" -H "Authorization: Bearer $TOKEN" "${@:3}" "$2")
  code=$(tail -n1 <<<"$out"); out=$(sed '$d' <<<"$out")
  if [ "$code" -ge 300 ]; then
    echo "Erro $code: $(python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("error",{}).get("message",""))' <<<"$out" 2>/dev/null || echo "$out")" >&2
    return 1
  fi
  echo "$out"
}
field() { python3 -I -c "import json,sys; print(json.load(sys.stdin)[sys.argv[1]])" "$1"; }

echo "→ A criar a edição…"
EDIT=$(call POST "$API/edits" | field id)
echo "→ A enviar $AAB ($(du -h "$AAB" | cut -f1))…"
CODE=$(call POST "$UPLOAD/edits/${EDIT}/bundles?uploadType=media" -H "Content-Type: application/octet-stream" --data-binary "@$AAB" | field versionCode)
echo "→ versionCode $CODE → faixa «${TRACK}» ($NAME)…"
call PUT "$API/edits/${EDIT}/tracks/${TRACK}" -H "Content-Type: application/json" \
  -d "{\"track\":\"$TRACK\",\"releases\":[{\"name\":\"$NAME\",\"versionCodes\":[\"$CODE\"],\"status\":\"completed\"}]}" >/dev/null
call POST "$API/edits/${EDIT}:commit" >/dev/null
echo "✓ Publicado no teste «${TRACK}»: $NAME"
