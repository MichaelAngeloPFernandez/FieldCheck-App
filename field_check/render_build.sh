#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.24.5"
FLUTTER_CHANNEL="stable"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/.render_flutter"
FLUTTER_DIR="$BUILD_DIR/flutter"

mkdir -p "$BUILD_DIR"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "==> Installing Flutter SDK ($FLUTTER_CHANNEL $FLUTTER_VERSION)"
  rm -rf "$FLUTTER_DIR"
  curl -L "https://storage.googleapis.com/flutter_infra_release/releases/$FLUTTER_CHANNEL/linux/flutter_linux_${FLUTTER_VERSION}-${FLUTTER_CHANNEL}.tar.xz" \
    -o "$BUILD_DIR/flutter.tar.xz"
  tar -xJf "$BUILD_DIR/flutter.tar.xz" -C "$BUILD_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

cd "$ROOT_DIR"

echo "==> Flutter version"
flutter --version

echo "==> Flutter config"
flutter config --enable-web

echo "==> Pub get"
flutter pub get

echo "==> Build web"
flutter build web --release

echo "==> Done. Publish directory: build/web"
