#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#
#   ██████╗ ██████╗ ██╗██╗   ██╗ █████╗ ████████╗███████╗
#   ██╔══██╗██╔══██╗██║██║   ██║██╔══██╗╚══██╔══╝██╔════╝
#   ██████╔╝██████╔╝██║██║   ██║███████║   ██║   █████╗
#   ██╔═══╝ ██╔══██╗██║╚██╗ ██╔╝██╔══██║   ██║   ██╔══╝
#   ██║     ██║  ██║██║ ╚████╔╝ ██║  ██║   ██║   ███████╗
#   ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚═╝  ╚═╝   ╚═╝   ╚══════╝
#   ████████╗██╗   ██╗███╗   ██╗███████╗███████╗
#   ╚══██╔══╝██║   ██║████╗  ██║██╔════╝██╔════╝
#      ██║   ██║   ██║██╔██╗ ██║█████╗  ███████╗
#      ██║   ██║   ██║██║╚██╗██║██╔══╝  ╚════██║
#      ██║   ╚██████╔╝██║ ╚████║███████╗███████║
#      ╚═╝    ╚═════╝ ╚═╝  ╚═══╝╚══════╝╚══════╝
#
#   Your private, self-hosted music server
#   Created by @Paidguy  |  https://github.com/Paidguy/PrivateTunes
#
# ─────────────────────────────────────────────────────────────────────────────

VERSION="3.0.0"

# ── Project Paths ─────────────────────────────────────────────────────────────
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$PROJECT_ROOT/scripts/privatetunes.sh"
LIB_DIR="$PROJECT_ROOT/scripts/lib"
BIN_DIR="$PROJECT_ROOT/bin"
SPOTIFLAC_CLI_BIN="$BIN_DIR/spotiflac-cli"
DEFAULT_OUTPUT_DIR="$PROJECT_ROOT/music"
LINKS_FILE="$PROJECT_ROOT/links.txt"
HISTORY_DIR="$PROJECT_ROOT/data"
HISTORY_FILE="$HISTORY_DIR/download_history.json"
HISTORY_LOCK="$HISTORY_DIR/.history.lock"

# ── Defaults ──────────────────────────────────────────────────────────────────
MAX_RETRIES=3
BASE_BACKOFF=5
RATE_LIMIT_WAIT=60
DOWNLOAD_TIMEOUT=300
UPDATE_CHECK_TIMEOUT=5
REMOTE_NAME="origin"
REMOTE_BRANCH="main"
DEBUG_MODE=0

# ── Parse CLI Flags ───────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --debug)  DEBUG_MODE=1 ;;
    --help)
      echo "Usage: privatetunes.sh [--debug] [--help]"
      echo "  --debug   Enable verbose debug logging"
      echo "  --help    Show this help message"
      exit 0
      ;;
  esac
done

# ── System Helpers ────────────────────────────────────────────────────────────
ensure_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_arch() {
  local arch; arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)  echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) err "Unsupported architecture: $arch"; return 1 ;;
  esac
}

# ── Source Modules ────────────────────────────────────────────────────────────
# Load all library modules from scripts/lib/
_load_module() {
  local module="$LIB_DIR/$1"
  if [ -f "$module" ]; then
    # shellcheck source=/dev/null
    source "$module"
  else
    echo "FATAL: Missing module: $module" >&2
    exit 1
  fi
}

_load_module "ui.sh"
_load_module "permissions.sh"
_load_module "updater.sh"
_load_module "api_resolver.sh"
_load_module "history.sh"
_load_module "downloader.sh"
_load_module "docker.sh"
_load_module "config.sh"
_load_module "onboarding.sh"

# ── Startup Sequence ──────────────────────────────────────────────────────────
# 1. Fix permissions (silent)
ensure_script_permissions

# Show debug banner if enabled
if [ "$DEBUG_MODE" = "1" ]; then
  printf "\n  ${YELLOW}${BOLD}⚙  DEBUG MODE ENABLED${NC}\n"
  printf "  ${DIM}Verbose output is active. Disable with: privatetunes.sh${NC}\n\n"
fi

# ── Main Menu ─────────────────────────────────────────────────────────────────
draw_menu() {
  local d_stat=1 n_stat=1 s_stat=1
  docker_ok    && d_stat=0
  navidrome_ok && n_stat=0
  syncthing_ok && s_stat=0

  local domain lib_size
  domain="$(get_env_val DOMAIN 'not set')"
  [ "$domain" = "your-domain.duckdns.org" ] && domain="not configured"
  lib_size="$(music_size)"

  local h_stats h_completed h_failed
  h_stats="$(history_stats)"
  h_completed=$(echo "$h_stats" | awk '{print $2}')
  h_failed=$(echo "$h_stats" | awk '{print $3}')

  clear || true
  printf "\n"

  # Branded header
  draw_header

  # Service status bar
  draw_status_bar "$d_stat" "$n_stat" "$s_stat" \
    "$domain" "$lib_size" "$h_completed" "$h_failed"

  # Menu sections
  section_header "SETUP"
  menu_item_pair "s" "Setup wizard" "h" "Help & docs"
  menu_item "u" "Check for updates" "pull latest from GitHub"

  section_header "MUSIC"
  menu_item_pair "1" "Install / update spotiflac" "2" "Download from URL"
  menu_item_pair "3" "View track metadata" "b" "Batch download (links.txt)"
  menu_item "d" "Download history" "view / clear / retry"

  section_header "DOCKER"
  menu_item_pair "4" "Start stack" "5" "Stop stack"
  menu_item_pair "6" "View logs" "7" "Stack status"
  menu_item "8" "Restart Navidrome"

  section_header "CONFIG"
  menu_item_pair "9" "Domain wizard" "c" "Backup config"
  menu_item_pair "p" "Paths & environment" "0" "Exit"
}

main_menu() {
  # 2. Check for updates (non-blocking)
  startup_update_check

  # 3. First-run onboarding
  maybe_first_run_onboard

  # 4. Auto-scan existing music
  maybe_auto_scan

  while true; do
    draw_menu
    menu_prompt
    local choice
    read -r choice
    case "$choice" in
      s|S) run_onboarding ;;
      h|H) show_help ;;
      u|U) action_check_update ;;
      1)   action_install_or_update ;;
      2)   action_download ;;
      3)   action_metadata ;;
      b|B) action_batch_download ;;
      d|D) action_download_history ;;
      4)   action_stack_up ;;
      5)   action_stack_down ;;
      6)   action_stack_logs ;;
      7)   action_stack_status ;;
      8)   action_stack_restart_navidrome ;;
      9)   onboard_domain ;;
      c|C) action_backup_config ;;
      p|P) action_print_paths ;;
      0)
        draw_goodbye
        exit 0
        ;;
      *)
        err "Invalid option '$choice'. Press [h] for help."
        sleep 1
        ;;
    esac
  done
}

main_menu
