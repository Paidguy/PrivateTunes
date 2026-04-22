#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"
SPOTIFLAC_CLI_BIN="$BIN_DIR/spotiflac-cli"
DEFAULT_OUTPUT_DIR="$PROJECT_ROOT/music"

# ── helpers ──────────────────────────────────────────────────────────────────

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
      echo "❌ Unsupported architecture: $arch"
      return 1
      ;;
  esac
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

require_docker() {
  if ! ensure_cmd docker; then
    echo "❌ Docker is not installed. Run: sudo ./scripts/setup.sh"
    pause
    return 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    echo "❌ Docker Compose plugin is missing. Run: sudo ./scripts/setup.sh"
    pause
    return 1
  fi
}

# ── spotiflac-cli ─────────────────────────────────────────────────────────────

install_spotiflac_cli() {
  local arch asset url
  arch="$(detect_arch)"
  asset="spotiflac-cli-linux-$arch"
  url="https://github.com/Superredstone/spotiflac-cli/releases/download/v1.0.0/$asset"

  echo "⬇️  Downloading spotiflac-cli ($asset)..."
  mkdir -p "$BIN_DIR"

  if ensure_cmd curl; then
    curl -fsSL "$url" -o "$SPOTIFLAC_CLI_BIN"
  elif ensure_cmd wget; then
    wget -q --show-progress -O "$SPOTIFLAC_CLI_BIN" "$url"
  else
    echo "❌ Neither curl nor wget found. Install one and re-run."
    return 1
  fi

  chmod +x "$SPOTIFLAC_CLI_BIN"
  echo "✅ Installed spotiflac-cli to $SPOTIFLAC_CLI_BIN"
}

require_spotiflac_cli() {
  if [ -x "$SPOTIFLAC_CLI_BIN" ]; then
    return 0
  fi
  echo "spotiflac-cli not found. Installing..."
  install_spotiflac_cli
}

ensure_env_file() {
  if [ -f "$PROJECT_ROOT/.env" ]; then
    return 0
  fi
  if [ -f "$PROJECT_ROOT/.env.example" ]; then
    cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
    echo "✅ Created .env from .env.example"
    echo "   Edit $PROJECT_ROOT/.env to set your DOMAIN."
  else
    echo "⚠️  .env.example not found. Cannot create .env automatically."
  fi
}

# ── menu actions ──────────────────────────────────────────────────────────────

action_full_setup() {
  echo "🚀 Running full setup (requires sudo for package installation)..."
  sudo "$PROJECT_ROOT/scripts/setup.sh"
  pause
}

action_install_or_update() {
  install_spotiflac_cli
  pause
}

action_download() {
  require_spotiflac_cli || return 1
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
  require_spotiflac_cli || return 1
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

action_configure_env() {
  ensure_env_file
  local editor="${VISUAL:-${EDITOR:-nano}}"
  if ensure_cmd "$editor"; then
    "$editor" "$PROJECT_ROOT/.env"
  else
    echo "⚠️  No editor found (tried $editor)."
    echo "   Manually edit: $PROJECT_ROOT/.env"
    pause
  fi
}

action_stack_up() {
  require_docker || return 1
  ensure_env_file
  cd "$PROJECT_ROOT"
  echo "🚀 Starting the stack..."
  docker compose up -d
  echo ""
  echo "⏳ Waiting for Navidrome to respond..."
  local retries=18
  until curl -sf http://localhost:4533/ping >/dev/null 2>&1; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "⚠️  Navidrome did not respond within 3 minutes."
      echo "   Check logs: docker compose logs navidrome"
      pause
      return 0
    fi
    sleep 10
  done
  echo "✅ Navidrome is up at http://localhost:4533"
  pause
}

action_stack_down() {
  require_docker || return 1
  cd "$PROJECT_ROOT"
  docker compose down
  pause
}

action_stack_logs() {
  require_docker || return 1
  echo "Tip: press Ctrl+C to stop following logs."
  cd "$PROJECT_ROOT"
  docker compose logs -f
}

action_stack_status() {
  require_docker || return 1
  cd "$PROJECT_ROOT"
  echo "=== Container status ==="
  docker compose ps
  echo ""
  echo "=== Navidrome health ==="
  if curl -sf http://localhost:4533/ping >/dev/null 2>&1; then
    echo "✅ Navidrome responding at http://localhost:4533"
  else
    echo "❌ Navidrome not responding on port 4533"
  fi
  echo ""
  echo "=== Syncthing health ==="
  if curl -sf http://localhost:8384/ >/dev/null 2>&1; then
    echo "✅ Syncthing responding at http://localhost:8384"
  else
    echo "❌ Syncthing not responding on port 8384"
  fi
  pause
}

action_stack_restart_navidrome() {
  require_docker || return 1
  cd "$PROJECT_ROOT"
  docker compose restart navidrome
  echo "✅ Navidrome restarted."
  pause
}

action_print_paths() {
  echo "Project root   : $PROJECT_ROOT"
  echo "Music folder   : $DEFAULT_OUTPUT_DIR"
  echo "Data folder    : $PROJECT_ROOT/data"
  echo "spotiflac-cli  : $SPOTIFLAC_CLI_BIN"
  echo ".env file      : $PROJECT_ROOT/.env"
  echo ""
  if [ -f "$PROJECT_ROOT/.env" ]; then
    echo "=== .env contents ==="
    cat "$PROJECT_ROOT/.env"
  fi
  pause
}

# ── main menu ─────────────────────────────────────────────────────────────────

main_menu() {
  while true; do
    clear || true
    echo "🎵 Cloud Music Stack — CLI Menu"
    echo "================================"
    echo " s) Full setup (install Docker, deps, start stack)"
    echo ""
    echo " --- spotiflac-cli ---"
    echo " 1) Install/Update spotiflac-cli"
    echo " 2) Download from Spotify URL"
    echo " 3) View track metadata"
    echo ""
    echo " --- Docker stack ---"
    echo " 4) Start stack   (docker compose up -d)"
    echo " 5) Stop stack    (docker compose down)"
    echo " 6) Stack logs    (docker compose logs -f)"
    echo " 7) Stack status  (health check)"
    echo " 8) Restart Navidrome"
    echo ""
    echo " --- Config ---"
    echo " 9) Edit .env (domain / uid / gid)"
    echo " p) Show important paths"
    echo ""
    echo " 0) Exit"
    echo
    local choice
    choice="$(prompt "Select an option: ")"
    case "$choice" in
      s|S) action_full_setup ;;
      1)   action_install_or_update ;;
      2)   action_download ;;
      3)   action_metadata ;;
      4)   action_stack_up ;;
      5)   action_stack_down ;;
      6)   action_stack_logs ;;
      7)   action_stack_status ;;
      8)   action_stack_restart_navidrome ;;
      9)   action_configure_env ;;
      p|P) action_print_paths ;;
      0)   exit 0 ;;
      *)   echo "❌ Invalid option."; pause ;;
    esac
  done
}

main_menu
