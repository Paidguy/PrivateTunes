#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"
SPOTIFLAC_CLI_BIN="$BIN_DIR/spotiflac-cli"
DEFAULT_OUTPUT_DIR="$PROJECT_ROOT/music"

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
    return 1
  fi

  chmod +x "$SPOTIFLAC_CLI_BIN"
  echo "✅ Installed to $SPOTIFLAC_CLI_BIN"
}

require_spotiflac_cli() {
  if [ -x "$SPOTIFLAC_CLI_BIN" ]; then
    return 0
  fi
  install_spotiflac_cli
}

ensure_env_file() {
  if [ -f "$PROJECT_ROOT/.env" ]; then
    return 0
  fi
  if [ -f "$PROJECT_ROOT/.env.example" ]; then
    cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
    echo "✅ Created .env from .env.example"
    echo "   -> Edit it if you want a custom DOMAIN."
  fi
}

pause() {
  read -r -p "Press Enter to continue..." _
}

prompt() {
  local label="${1:?label required}"
  local value
  read -r -p "$label" value
  printf '%s' "$value"
}

action_install_or_update() {
  install_spotiflac_cli
  pause
}

action_download() {
  require_spotiflac_cli
  mkdir -p "$DEFAULT_OUTPUT_DIR"
  local url
  url="$(prompt "Spotify URL (track/album/playlist): ")"
  if [ -z "$url" ]; then
    echo "❌ URL is required."
    pause
    return 1
  fi

  echo "📥 Downloading to: $DEFAULT_OUTPUT_DIR"
  "$SPOTIFLAC_CLI_BIN" download "$url" --output "$DEFAULT_OUTPUT_DIR"
  echo "✅ Done."
  pause
}

action_metadata() {
  require_spotiflac_cli
  local url
  url="$(prompt "Spotify URL (track): ")"
  if [ -z "$url" ]; then
    echo "❌ URL is required."
    pause
    return 1
  fi

  "$SPOTIFLAC_CLI_BIN" metadata "$url"
  pause
}

action_stack_up() {
  ensure_env_file
  if ! ensure_cmd docker; then
    echo "❌ docker is not installed or not in PATH."
    pause
    return 1
  fi
  docker compose up -d
  pause
}

action_stack_down() {
  if ! ensure_cmd docker; then
    echo "❌ docker is not installed or not in PATH."
    pause
    return 1
  fi
  docker compose down
  pause
}

action_stack_logs() {
  if ! ensure_cmd docker; then
    echo "❌ docker is not installed or not in PATH."
    pause
    return 1
  fi
  echo "Tip: press Ctrl+C to stop following logs."
  docker compose logs -f
}

action_print_paths() {
  echo "Project root: $PROJECT_ROOT"
  echo "Music folder:  $DEFAULT_OUTPUT_DIR"
  echo "Data folder:   $PROJECT_ROOT/data"
  echo "spotiflac-cli: $SPOTIFLAC_CLI_BIN"
  pause
}

main_menu() {
  while true; do
    clear || true
    echo "🎵 Cloud Music Stack — CLI Menu"
    echo "--------------------------------"
    echo "1) Install/Update spotiflac-cli"
    echo "2) Download from Spotify URL"
    echo "3) View track metadata"
    echo "4) Start stack (docker compose up -d)"
    echo "5) Stop stack (docker compose down)"
    echo "6) View stack logs (docker compose logs -f)"
    echo "7) Show important paths"
    echo "0) Exit"
    echo
    local choice
    choice="$(prompt "Select an option: ")"
    case "$choice" in
      1) action_install_or_update ;;
      2) action_download ;;
      3) action_metadata ;;
      4) action_stack_up ;;
      5) action_stack_down ;;
      6) action_stack_logs ;;
      7) action_print_paths ;;
      0) exit 0 ;;
      *) echo "❌ Invalid option."; pause ;;
    esac
  done
}

main_menu

