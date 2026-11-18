#!/usr/bin/env bash
# Compile le moteur Rust, copie la bibliothèque statique, puis compile l'application.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Moteur Rust (release)"
cargo build --release -p mission-token-ffi

echo "==> Bibliothèque statique"
mkdir -p Sources/CMissionTokenFFI/lib
cp target/release/libmission_token_ffi.a Sources/CMissionTokenFFI/lib/

echo "==> Application SwiftUI"
swift build -c release --product MissionTokenLive

echo "==> Bundle .app"
APP="dist/MissionTokenLive.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MissionTokenLive "$APP/Contents/MacOS/"
cp packaging/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" 2>/dev/null || true
echo "OK : $APP"
