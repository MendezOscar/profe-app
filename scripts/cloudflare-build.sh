#!/usr/bin/env bash
# Build de la web en Cloudflare Pages. Su imagen no trae Flutter: se baja la misma versión
# que usa el CI. Salida: mobile/build/web. Requiere la variable API_BASE_URL en Pages.
set -euo pipefail

if [ -z "${API_BASE_URL:-}" ]; then
  echo "Falta la variable API_BASE_URL en Cloudflare Pages." >&2
  exit 1
fi

FLUTTER_DIR="${HOME}/flutter"
if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b 3.35.1 --depth 1 "${FLUTTER_DIR}"
fi
export PATH="${FLUTTER_DIR}/bin:${PATH}"

cd "$(dirname "$0")/../mobile"
flutter config --no-analytics --enable-web
flutter pub get
# web/sqlite3.wasm y web/sqflite_sw.js ya están en el repo: la base local funciona sin pasos extra.
flutter build web --release --dart-define=API_BASE_URL="${API_BASE_URL}"
