#!/usr/bin/env bash

set -euo pipefail

FLUTTER_SDK_DIR="${VERCEL_CACHE_DIR:-/tmp/classcard-vercel-cache}/flutter-sdk"

if [[ ! -x "${FLUTTER_SDK_DIR}/bin/flutter" ]]; then
  rm -rf "${FLUTTER_SDK_DIR}"
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "${FLUTTER_SDK_DIR}"
fi

"${FLUTTER_SDK_DIR}/bin/flutter" config --enable-web
"${FLUTTER_SDK_DIR}/bin/flutter" pub get
"${FLUTTER_SDK_DIR}/bin/flutter" build web --release
