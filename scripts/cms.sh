#!/bin/bash

# Cloud Music Stack — Interactive CLI Menu
# Created by @Paidguy  |  https://github.com/Paidguy/music

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"
SPOTIFLAC_CLI_BIN="$BIN_DIR/spotiflac-cli"
DEFAULT_OUTPUT_DIR="$PROJECT_ROOT/music"

# ── colour palette ────────────────────────────────────────────────────────────
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
  WHITE='\033[0;37m'
else
  BOLD=''; DIM=''; NC=''
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; MAGENTA=''; WHITE=''
fi

# ── UI primitives ─────────────────────────────────────────────────────────────
ok()   { printf "  ${GREEN}${BOLD}✔${NC}  %s\n" "$*"; }
warn() { printf "  ${YELLOW}${BOLD}⚠${NC}   %s\n" "$*"; }
err()  { printf "  ${RED}${BOLD}✘${NC}  %s\n" "$*" >&2; }
info() { printf "  ${CYAN}▸${NC}  %s\n" "$*"; }
hr()   { printf "${CYAN}──────────────────────────────────────────────────────────${NC}\n"; }

pause() { printf "\n"; read -r -p "  Press Enter to continue…" _; }

prompt() {
  local label="${1:?label required}"
  local val
  printf "  ${YELLOW}?${NC}  ${BOLD}%s${NC} " "$label"
  read -r val
  printf '%s' "$val"
}

prompt_val() {
  local label="$1" default="${2:-}"
  local val
  if [ -n "$default" ]; then
    printf "  ${YELLOW}?${NC}  ${BOLD}%s${NC} [%s]: " "$label" "$default"
  else
    printf "  ${YELLOW}?${NC}  ${BOLD}%s${NC}: " "$label"
  fi
  read -r val
  printf '%s' "${val:-$default}"
}

# confirm Y/n (default YES)
confirm() {
  local msg="${1:-Continue?}"
  local ans
  printf "  ${YELLOW}?${NC}  ${BOLD}%s${NC} [Y/n] " "$msg"
  read -r ans
  case "$ans" in [nN]*) return 1 ;; *) return 0 ;; esac
}

# ── live status helpers ───────────────────────────────────────────────────────
docker_ok() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

navidrome_ok() {
  curl -sf --max-time 2 http://localhost:4533/ping >/dev/null 2>&1
}

syncthing_ok() {
  curl -sf --max-time 2 http://localhost:8384/ >/dev/null 2>&1
}

status_badge() {
  # $1 = label, $2 = 0|1 (ok=0, fail=1)
  if [ "$2" -eq 0 ]; then
    printf "${GREEN}${BOLD}● %-12s${NC}" "$1"
  else
    printf "${RED}${BOLD}○ %-12s${NC}" "$1"
  fi
}

# ── system helpers ────────────────────────────────────────────────────────────
ensure_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_arch() {
  local arch; arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)  echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) err "Unsupported architecture: $arch"; return 1 ;;
  esac
}

require_docker() {
  if ! docker_ok; then
    err "Docker is not installed or the Compose plugin is missing."
    info "Fix it by running option [s] Full Setup."
    pause; return 1
  fi
}

# ── spotiflac-cli ─────────────────────────────────────────────────────────────
install_spotiflac_cli() {
  local arch asset url
  arch="$(detect_arch)"
  asset="spotiflac-cli-linux-$arch"
  url="https://github.com/Superredstone/spotiflac-cli/releases/download/v1.0.0/$asset"

  info "Downloading spotiflac-cli ($asset)…"
  mkdir -p "$BIN_DIR"

  if ensure_cmd curl; then
    curl -fsSL "$url" -o "$SPOTIFLAC_CLI_BIN"
  elif ensure_cmd wget; then
    wget -q --show-progress -O "$SPOTIFLAC_CLI_BIN" "$url"
  else
    err "Neither curl nor wget found. Install one and re-run."
    return 1
  fi

  chmod +x "$SPOTIFLAC_CLI_BIN"
  ok "spotiflac-cli installed → $SPOTIFLAC_CLI_BIN"
}

require_spotiflac_cli() {
  if [ -x "$SPOTIFLAC_CLI_BIN" ]; then return 0; fi
  info "spotiflac-cli not found — installing now…"
  install_spotiflac_cli
}

ensure_env_file() {
  if [ -f "$PROJECT_ROOT/.env" ]; then return 0; fi
  if [ -f "$PROJECT_ROOT/.env.example" ]; then
    cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
    ok "Created .env from .env.example."
  else
    warn ".env.example not found. Cannot create .env automatically."
  fi
}

# ── domain onboarding wizard ──────────────────────────────────────────────────
onboard_domain() {
  clear || true
  printf "${CYAN}"
  printf '╔══════════════════════════════════════════════════════════╗\n'
  printf '║   🌐  Domain Setup Wizard                               ║\n'
  printf '╚══════════════════════════════════════════════════════════╝\n'
  printf "${NC}\n"

  info "Caddy needs a public domain name to issue a free HTTPS certificate."
  info "A free subdomain from DuckDNS works perfectly:"
  printf "\n  ${BLUE}${BOLD}https://www.duckdns.org${NC}\n\n"
  info "Steps to get a free DuckDNS domain:"
  printf "    1. Visit https://www.duckdns.org and log in with GitHub/Google\n"
  printf "    2. Enter a subdomain name and click 'add domain'\n"
  printf "    3. Point the domain to this server's public IP\n"
  printf "    4. Enter your full domain below (e.g. mymusic.duckdns.org)\n\n"
  info "You can skip this and set a real domain later. The stack will still"
  info "run locally on http://localhost:4533 without a domain."
  printf "\n"

  ensure_env_file

  local current_domain
  current_domain="$(grep '^DOMAIN=' "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo 'your-domain.duckdns.org')"

  local new_domain
  new_domain="$(prompt_val "Your domain name" "$current_domain")"

  if [ -z "$new_domain" ] || [ "$new_domain" = "your-domain.duckdns.org" ]; then
    warn "Keeping placeholder domain. HTTPS won't work until you set a real one."
    new_domain="your-domain.duckdns.org"
  else
    ok "Domain → $new_domain"
  fi

  # Write DOMAIN
  if grep -q '^DOMAIN=' "$PROJECT_ROOT/.env" 2>/dev/null; then
    sed -i "s|^DOMAIN=.*|DOMAIN=$new_domain|" "$PROJECT_ROOT/.env"
  else
    echo "DOMAIN=$new_domain" >> "$PROJECT_ROOT/.env"
  fi

  printf "\n"
  info "Syncthing uses your system UID/GID to manage file ownership."
  local uid_val gid_val
  uid_val="$(prompt_val "UID" "$(id -u)")"
  gid_val="$(prompt_val "GID" "$(id -g)")"

  if grep -q '^UID=' "$PROJECT_ROOT/.env" 2>/dev/null; then
    sed -i "s|^UID=.*|UID=$uid_val|" "$PROJECT_ROOT/.env"
  else
    echo "UID=$uid_val" >> "$PROJECT_ROOT/.env"
  fi
  if grep -q '^GID=' "$PROJECT_ROOT/.env" 2>/dev/null; then
    sed -i "s|^GID=.*|GID=$gid_val|" "$PROJECT_ROOT/.env"
  else
    echo "GID=$gid_val" >> "$PROJECT_ROOT/.env"
  fi

  printf "\n"
  ok ".env saved."
  info "If you changed the domain, restart the stack (option 4) for Caddy to"
  info "pick up the new certificate."
  pause
}

# ── help screen ───────────────────────────────────────────────────────────────
show_help() {
  clear || true
  printf "${CYAN}"
  printf '╔══════════════════════════════════════════════════════════╗\n'
  printf '║   ❓  Cloud Music Stack — Help                          ║\n'
  printf '╚══════════════════════════════════════════════════════════╝\n'
  printf "${NC}\n"

  printf "${BOLD}${BLUE}OVERVIEW${NC}\n"
  hr
  printf "  Cloud Music Stack lets you self-host a personal music server\n"
  printf "  (Navidrome) with automatic HTTPS (Caddy) and optional sync\n"
  printf "  across devices (Syncthing). Music is downloaded via spotiflac-cli.\n\n"

  printf "${BOLD}${BLUE}OPTION GUIDE${NC}\n"
  hr
  printf "  ${BOLD}[s]${NC} Full Setup       Run the automated setup wizard (installs Docker,\n"
  printf "                     downloads spotiflac-cli, configures .env, starts stack).\n\n"
  printf "  ${BOLD}[1]${NC} Install/Update   Download the latest spotiflac-cli binary.\n\n"
  printf "  ${BOLD}[2]${NC} Download music   Paste any Spotify track, album, or playlist URL\n"
  printf "                     to download it as FLAC into ./music/.\n\n"
  printf "  ${BOLD}[3]${NC} Track metadata   View metadata for a Spotify track URL.\n\n"
  printf "  ${BOLD}[4]${NC} Start stack      docker compose up -d  (also waits for Navidrome).\n\n"
  printf "  ${BOLD}[5]${NC} Stop stack       docker compose down.\n\n"
  printf "  ${BOLD}[6]${NC} Stack logs       Follow live logs from all containers.\n\n"
  printf "  ${BOLD}[7]${NC} Stack status     Show container state + health checks.\n\n"
  printf "  ${BOLD}[8]${NC} Restart Navidrome Restart only the Navidrome container.\n\n"
  printf "  ${BOLD}[9]${NC} Domain setup     Interactive wizard to set your domain name and\n"
  printf "                     UID/GID in .env. Guides you through DuckDNS.\n\n"
  printf "  ${BOLD}[p]${NC} Paths            Show all important paths and current .env.\n\n"
  printf "  ${BOLD}[h]${NC} Help             Show this screen.\n\n"
  printf "  ${BOLD}[0]${NC} Exit             Quit the menu.\n\n"

  printf "${BOLD}${BLUE}KEY PORTS${NC}\n"
  hr
  printf "  4533  Navidrome web UI + Subsonic API\n"
  printf "  8384  Syncthing web UI\n"
  printf "  80    Caddy HTTP (redirects to HTTPS)\n"
  printf "  443   Caddy HTTPS\n\n"

  printf "${BOLD}${BLUE}TROUBLESHOOTING${NC}\n"
  hr
  printf "  Music not scanning?   Restart Navidrome (option 8) or trigger a\n"
  printf "                        manual library scan in the Navidrome web UI.\n\n"
  printf "  HTTPS not working?    Check that your DOMAIN is correct in .env,\n"
  printf "                        ports 80/443 are open, and DNS points to this\n"
  printf "                        server. Then restart the stack (option 4).\n\n"
  printf "  Container issues?     Use option 6 to view logs.\n\n"

  printf "${DIM}  Created by @Paidguy  •  https://github.com/Paidguy/music${NC}\n\n"
  pause
}

# ── menu actions ──────────────────────────────────────────────────────────────
action_full_setup() {
  printf "\n"
  info "Delegating to setup.sh (may ask for sudo)…"
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
  url="$(prompt "Spotify URL (track / album / playlist):")"
  if [ -z "$url" ]; then
    err "URL is required."; pause; return 1
  fi
  printf "\n"
  info "Downloading to: $DEFAULT_OUTPUT_DIR"
  "$SPOTIFLAC_CLI_BIN" download "$url" --output "$DEFAULT_OUTPUT_DIR"
  ok "Done."
  pause
}

action_metadata() {
  require_spotiflac_cli || return 1
  local url
  url="$(prompt "Spotify track URL:")"
  if [ -z "$url" ]; then
    err "URL is required."; pause; return 1
  fi
  printf "\n"
  "$SPOTIFLAC_CLI_BIN" metadata "$url"
  pause
}

action_stack_up() {
  require_docker || return 1
  ensure_env_file
  cd "$PROJECT_ROOT"
  info "Starting the stack…"
  docker compose up -d
  printf "\n"
  info "Waiting for Navidrome to respond…"
  local retries=18
  until curl -sf --max-time 2 http://localhost:4533/ping >/dev/null 2>&1; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      warn "Navidrome did not respond within 3 minutes."
      info "Check logs: docker compose logs navidrome"
      pause; return 0
    fi
    printf "."
    sleep 10
  done
  printf "\n"
  ok "Navidrome is up → http://localhost:4533"
  pause
}

action_stack_down() {
  require_docker || return 1
  cd "$PROJECT_ROOT"
  docker compose down
  ok "Stack stopped."
  pause
}

action_stack_logs() {
  require_docker || return 1
  info "Press Ctrl+C to stop following logs."
  cd "$PROJECT_ROOT"
  docker compose logs -f
}

action_stack_status() {
  require_docker || return 1
  cd "$PROJECT_ROOT"
  printf "\n${BOLD}Container status${NC}\n"; hr
  docker compose ps
  printf "\n${BOLD}Health checks${NC}\n"; hr
  if navidrome_ok; then
    ok "Navidrome  → http://localhost:4533"
  else
    err "Navidrome not responding on :4533"
  fi
  if syncthing_ok; then
    ok "Syncthing  → http://localhost:8384"
  else
    warn "Syncthing not responding on :8384 (may be disabled)"
  fi
  pause
}

action_stack_restart_navidrome() {
  require_docker || return 1
  cd "$PROJECT_ROOT"
  info "Restarting Navidrome…"
  docker compose restart navidrome
  ok "Navidrome restarted."
  pause
}

action_print_paths() {
  printf "\n${BOLD}Important paths${NC}\n"; hr
  printf "  Project root   : %s\n" "$PROJECT_ROOT"
  printf "  Music folder   : %s\n" "$DEFAULT_OUTPUT_DIR"
  printf "  Data folder    : %s\n" "$PROJECT_ROOT/data"
  printf "  spotiflac-cli  : %s\n" "$SPOTIFLAC_CLI_BIN"
  printf "  .env file      : %s\n" "$PROJECT_ROOT/.env"
  if [ -f "$PROJECT_ROOT/.env" ]; then
    printf "\n${BOLD}.env contents${NC}\n"; hr
    # mask no secrets but show file clearly
    sed 's/^/  /' "$PROJECT_ROOT/.env"
  fi
  pause
}

# ── first-run onboarding check ────────────────────────────────────────────────
# If .env doesn't exist OR the domain is still the placeholder, prompt the user.
maybe_first_run_onboard() {
  local domain
  domain="$(grep '^DOMAIN=' "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo '')"
  if [ ! -f "$PROJECT_ROOT/.env" ] || [ -z "$domain" ] || [ "$domain" = "your-domain.duckdns.org" ]; then
    clear || true
    printf "${CYAN}"
    printf '╔══════════════════════════════════════════════════════════╗\n'
    printf '║   👋  Welcome to Cloud Music Stack!                     ║\n'
    printf '║      by @Paidguy  —  github.com/Paidguy/music           ║\n'
    printf '╚══════════════════════════════════════════════════════════╝\n'
    printf "${NC}\n"
    info "It looks like this is your first time running the stack,"
    info "or your domain hasn't been configured yet."
    printf "\n"
    if confirm "Run the quick onboarding wizard now?"; then
      ensure_env_file
      onboard_domain
    else
      info "Skipped. You can run it anytime via option [9] in the menu."
    fi
  fi
}

# ── main menu ─────────────────────────────────────────────────────────────────
draw_menu() {
  # Collect live status (fast, timeout 2s each)
  local d_stat=1 n_stat=1 s_stat=1
  docker_ok    && d_stat=0
  navidrome_ok && n_stat=0
  syncthing_ok && s_stat=0

  local domain
  domain="$(grep '^DOMAIN=' "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo 'not configured')"

  clear || true
  printf "${CYAN}"
  printf '╔══════════════════════════════════════════════════════════╗\n'
  printf '║   🎵  Cloud Music Stack          by @Paidguy             ║\n'
  printf '║      github.com/Paidguy/music                           ║\n'
  printf '╠══════════════════════════════════╦══════════════════════╣\n'
  printf '║                                  ║  STATUS              ║\n'
  printf "║  ${BOLD}${YELLOW}[s]${NC}${CYAN} Full Setup / Onboarding   ${CYAN}║  "; status_badge "Docker"    $d_stat; printf "  ${CYAN}║\n"
  printf "║  ${BOLD}${YELLOW}[h]${NC}${CYAN} Help                      ${CYAN}║  "; status_badge "Navidrome" $n_stat; printf "  ${CYAN}║\n"
  printf "║                                  ║  "; status_badge "Syncthing" $s_stat; printf "  ${CYAN}║\n"
  printf '╠══════════════════════════════════╩══════════════════════╣\n'
  printf "║  ${BOLD}MUSIC TOOLS${NC}${CYAN}                                         ║\n"
  printf "║  ${BOLD}${YELLOW}[1]${NC}${CYAN} Install / Update spotiflac-cli                  ║\n"
  printf "║  ${BOLD}${YELLOW}[2]${NC}${CYAN} Download music from Spotify URL                 ║\n"
  printf "║  ${BOLD}${YELLOW}[3]${NC}${CYAN} View track metadata                             ║\n"
  printf '╠══════════════════════════════════════════════════════════╣\n'
  printf "║  ${BOLD}DOCKER STACK${NC}${CYAN}                                        ║\n"
  printf "║  ${BOLD}${YELLOW}[4]${NC}${CYAN} Start stack     ${BOLD}${YELLOW}[5]${NC}${CYAN} Stop stack                  ║\n"
  printf "║  ${BOLD}${YELLOW}[6]${NC}${CYAN} View logs       ${BOLD}${YELLOW}[7]${NC}${CYAN} Stack status                ║\n"
  printf "║  ${BOLD}${YELLOW}[8]${NC}${CYAN} Restart Navidrome                               ║\n"
  printf '╠══════════════════════════════════════════════════════════╣\n'
  printf "║  ${BOLD}CONFIGURATION${NC}${CYAN}                                       ║\n"
  printf "║  ${BOLD}${YELLOW}[9]${NC}${CYAN} Domain setup wizard                             ║\n"
  printf "║  ${BOLD}${YELLOW}[p]${NC}${CYAN} Show paths / .env                               ║\n"
  printf "║  %-57s║\n" "Domain: ${NC}${WHITE}$domain${CYAN}"
  printf '╠══════════════════════════════════════════════════════════╣\n'
  printf "║  ${BOLD}${YELLOW}[0]${NC}${CYAN} Exit                                            ║\n"
  printf '╚══════════════════════════════════════════════════════════╝\n'
  printf "${NC}"
}

main_menu() {
  maybe_first_run_onboard

  while true; do
    draw_menu
    printf "\n  ${BOLD}Select an option:${NC} "
    local choice
    read -r choice
    case "$choice" in
      s|S) action_full_setup ;;
      h|H) show_help ;;
      1)   action_install_or_update ;;
      2)   action_download ;;
      3)   action_metadata ;;
      4)   action_stack_up ;;
      5)   action_stack_down ;;
      6)   action_stack_logs ;;
      7)   action_stack_status ;;
      8)   action_stack_restart_navidrome ;;
      9)   onboard_domain ;;
      p|P) action_print_paths ;;
      0)
        printf "\n  ${DIM}Goodbye! — @Paidguy${NC}\n\n"
        exit 0
        ;;
      *)
        err "Invalid option '$choice'. Press [h] for help."
        pause
        ;;
    esac
  done
}

main_menu
