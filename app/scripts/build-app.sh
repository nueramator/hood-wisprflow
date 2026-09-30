#!/usr/bin/env bash
# Builds WisprFlow and assembles a proper .app bundle (unsigned, ad-hoc signed
# for a stable identity so macOS permissions stick across rebuilds).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/WisprFlow.app"
CONFIG="release"

echo "==> Building (swift build -c $CONFIG)"
swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/WisprFlow"
if [ ! -f "$BIN" ]; then
  echo "!! Build produced no binary at $BIN"; exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WisprFlow"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Ad-hoc code signing (stable identity for TCC permissions)"
codesign --force --deep --sign - "$APP"

echo ""
echo "Built: $APP"
echo ""
echo "First run:"
echo "  1. open \"$APP\"   (or double-click it in Finder)"
echo "  2. Grant Microphone AND Accessibility when prompted"
echo "     (System Settings ▸ Privacy & Security ▸ Accessibility — add Wispr Flow)"
echo "  3. If you enabled AI cleanup, launch with your key so the app inherits it:"
echo "     ANTHROPIC_API_KEY=sk-ant-... open \"$APP\""
echo ""
echo "Then hold  ⌥Space  anywhere, speak, release — text appears at your cursor."
