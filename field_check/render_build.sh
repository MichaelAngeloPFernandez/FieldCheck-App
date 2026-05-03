#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.41.4"
FLUTTER_CHANNEL="stable"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/.render_flutter"
FLUTTER_DIR="$BUILD_DIR/flutter"

VERSION_FILE="$BUILD_DIR/.flutter_version"

mkdir -p "$BUILD_DIR"

NEED_INSTALL="false"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  NEED_INSTALL="true"
elif [ ! -f "$VERSION_FILE" ]; then
  NEED_INSTALL="true"
elif [ "$(cat "$VERSION_FILE")" != "$FLUTTER_VERSION" ]; then
  NEED_INSTALL="true"
fi

if [ "$NEED_INSTALL" = "true" ]; then
  echo "==> Installing Flutter SDK ($FLUTTER_CHANNEL $FLUTTER_VERSION)"
  rm -rf "$FLUTTER_DIR"
  curl -L "https://storage.googleapis.com/flutter_infra_release/releases/$FLUTTER_CHANNEL/linux/flutter_linux_${FLUTTER_VERSION}-${FLUTTER_CHANNEL}.tar.xz" \
    -o "$BUILD_DIR/flutter.tar.xz"
  tar -xJf "$BUILD_DIR/flutter.tar.xz" -C "$BUILD_DIR"
  echo "$FLUTTER_VERSION" > "$VERSION_FILE"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

cd "$ROOT_DIR"

echo "==> Flutter version"
flutter --version

echo "==> Disable analytics"
flutter config --no-analytics

echo "==> Flutter config"
flutter config --enable-web

echo "==> Pub get"
flutter pub get

echo "==> Build web"
flutter build web --release

echo "==> Done. Publish directory: build/web"
