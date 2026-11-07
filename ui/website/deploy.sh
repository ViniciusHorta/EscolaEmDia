#!/usr/bin/env bash
# Publica o site institucional (ui/website/public) no Cloudflare Pages.
# A app continua a ser publicada pelo ../../deploy.sh em app.escolaemdia.me.
set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-escolaemdia-site}"
cd "$(dirname "$0")"   # ./functions (páginas legais) é incluído a partir daqui
DIR="public"

command -v npx >/dev/null 2>&1 || { echo "Erro: npx não encontrado."; exit 1; }

# Cria o projeto na primeira vez (ignora o erro se já existir).
npx wrangler pages project create "$PROJECT_NAME" --production-branch=main 2>/dev/null || true

npx wrangler pages deploy "$DIR" --project-name="$PROJECT_NAME" --branch=main --commit-dirty=true

echo "Publicado. Liga o domínio escolaemdia.me em:"
echo "Cloudflare → Workers & Pages → $PROJECT_NAME → Custom domains"
