#!/bin/bash

set -euo pipefail

echo "🎵 Starting Music Stack Setup (CLI Edition)..."

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"
SPOTIFLAC_CLI_BIN="$BIN_DIR/spotiflac-cli"

ensure_cmd() {
  command -v "$1" >/dev/null 2>&1
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      echo "unsupported"
      return 1
      ;;
  esac
}

install_spotiflac_cli() {
  local arch asset url
  arch="$(detect_arch)"
  asset="spotiflac-cli-linux-$arch"
  url="https://github.com/Superredstone/spotiflac-cli/releases/download/v1.0.0/$asset"

  echo "⬇️ Installing spotiflac-cli ($asset)..."
  mkdir -p "$BIN_DIR"

  if ensure_cmd curl; then
    curl -fsSL "$url" -o "$SPOTIFLAC_CLI_BIN"
  elif ensure_cmd wget; then
    wget -q --show-progress -O "$SPOTIFLAC_CLI_BIN" "$url"
  else
    echo "❌ Missing downloader. Install either 'curl' or 'wget' and retry."
    exit 1
  fi

  chmod +x "$SPOTIFLAC_CLI_BIN"
  echo "   -> Installed to $SPOTIFLAC_CLI_BIN"
}

echo "📦 Installing system dependencies (no GUI)..."
if ensure_cmd apt-get; then
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates git
else
  echo "⚠️ apt-get not found. Skipping OS package install."
  echo "   Ensure you have: curl (or wget), ca-certificates, git"
fi

echo "📁 Ensuring project directories exist..."
mkdir -p "$PROJECT_ROOT/music" "$PROJECT_ROOT/data/navidrome" "$PROJECT_ROOT/data/syncthing"

if [ ! -f "$SPOTIFLAC_CLI_BIN" ]; then
  install_spotiflac_cli
else
  echo "✅ spotiflac-cli already present at $SPOTIFLAC_CLI_BIN"
fi

echo "✅ Setup Complete!"
echo "------------------------------------------------"
echo "NEXT STEPS:"
echo "1. (Optional) Configure DOMAIN: cp .env.example .env && nano .env"
echo "2. Start the music server: docker compose up -d"
echo "3. Download music: ./scripts/cms.sh"
echo "------------------------------------------------"
