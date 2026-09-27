#!/usr/bin/env bash
# Build del sitio en Cloudflare Pages. Su imagen no trae Flutter: se baja la misma versión
# que usa el CI. Requiere la variable API_BASE_URL en Pages.
#
# Salida (sin cambiar la configuración de Pages): mobile/build/web con
#   /            landing y páginas legales (site/)
#   /app/        el panel Flutter
#   _worker.js   enrutado entre las dos
set -euo pipefail

if [ -z "${API_BASE_URL:-}" ]; then
  echo "Falta la variable API_BASE_URL en Cloudflare Pages." >&2
  exit 1
fi

FLUTTER_DIR="${HOME}/flutter"
if [ ! -x "${FLUTTER_DIR}/bin/flutter" ] && ! command -v flutter >/dev/null; then
  git clone https://github.com/flutter/flutter.git -b 3.35.1 --depth 1 "${FLUTTER_DIR}"
fi
export PATH="${FLUTTER_DIR}/bin:${PATH}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}/mobile"
flutter config --no-analytics --enable-web
flutter pub get
# web/sqlite3.wasm y web/sqflite_sw.js ya están en el repo: la base local funciona sin pasos extra.
flutter build web --release --base-href /app/ --dart-define=API_BASE_URL="${API_BASE_URL}"

# El panel pasa a /app y el sitio ocupa la raíz.
rm -rf build/panel
mv build/web build/panel
mkdir -p build/web
mv build/panel build/web/app
cp "${ROOT}"/site/* build/web/
# El _redirects del bundle de Flutter no aplica: el enrutado lo hace _worker.js.
rm -f build/web/app/_redirects
