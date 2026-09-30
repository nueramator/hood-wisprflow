#!/usr/bin/env bash
# One-time setup for Wispr Flow: installs the local Whisper engine and model.
set -euo pipefail

SUPPORT_DIR="$HOME/Library/Application Support/WisprFlow"
MODEL_DIR="$SUPPORT_DIR/models"
MODEL_FILE="$MODEL_DIR/ggml-base.en.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

echo "==> Installing whisper.cpp (local, Metal-accelerated speech engine)"
if ! brew list whisper-cpp >/dev/null 2>&1; then
  brew install whisper-cpp
else
  echo "    whisper-cpp already installed"
fi

SERVER_BIN="$(command -v whisper-server || true)"
if [ -z "$SERVER_BIN" ]; then
  echo "!! whisper-server not found on PATH after install."
  echo "   Check 'brew --prefix'/bin and update whisperServerPath in config.json."
else
  echo "    whisper-server: $SERVER_BIN"
fi

echo "==> Downloading Whisper model (base.en, ~148 MB)"
mkdir -p "$MODEL_DIR"
if [ -f "$MODEL_FILE" ]; then
  echo "    Model already present: $MODEL_FILE"
else
  curl -L --fail --progress-bar "$MODEL_URL" -o "$MODEL_FILE"
fi

# The app writes its own config.json on first launch (default server path is
# /opt/homebrew/bin/whisper-server on Apple Silicon). If Homebrew put the binary
# elsewhere, edit whisperServerPath in:
#   ~/Library/Application Support/WisprFlow/config.json
if [ -n "$SERVER_BIN" ] && [ "$SERVER_BIN" != "/opt/homebrew/bin/whisper-server" ]; then
  echo ""
  echo "NOTE: whisper-server is at $SERVER_BIN"
  echo "      After first launch, set whisperServerPath to this in config.json."
fi

echo ""
echo "Setup complete."
echo "Next: ./scripts/build-app.sh   then open the built app."
