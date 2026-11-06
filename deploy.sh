
#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="escolaemdia"

echo "=================================="
echo " Escola em Dia - Deploy Cloudflare"
echo "=================================="

# 1. Verificar dependências
command -v flutter >/dev/null 2>&1 || {
  echo "Erro: Flutter não encontrado."
  exit 1
}

command -v npx >/dev/null 2>&1 || {
  echo "Erro: npx não encontrado."
  exit 1
}

# 2. Instalar dependências Flutter
echo "Instalando dependências..."
flutter pub get

# 3. Compilar aplicação
echo "Compilando Flutter Web..."
flutter build web --release

# 4. Verificar resultado
if [ ! -f "build/web/index.html" ]; then
  echo "Erro: build/web/index.html não encontrado."
  exit 1
fi

# 5. Publicar no Cloudflare Pages
echo "Publicando no Cloudflare..."
npx wrangler pages deploy build/web \
  --project-name="$PROJECT_NAME" \
  --branch=main

echo "=================================="
echo " Deploy concluído!"
echo " https://app.escolaemdia.me"
echo "=================================="
