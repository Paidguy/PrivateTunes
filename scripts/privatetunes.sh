#!/bin/bash

# PrivateTunes — Interactive CLI Menu
# Created by @Paidguy  |  https://github.com/Paidguy/PrivateTunes

VERSION="1.0.0"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"
SPOTIFLAC_CLI_BIN="$BIN_DIR/spotiflac-cli"
DEFAULT_OUTPUT_DIR="$PROJECT_ROOT/music"
LINKS_FILE="$PROJECT_ROOT/links.txt"

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
  local label="${1:?label required}" val
  printf "  ${YELLOW}?${NC}  ${BOLD}%s${NC} " "$label" >&2
  read -r val
  printf '%s' "$val"
}

prompt_val() {
  local label="$1" default="${2:-}" val
  if [ -n "$default" ]; then
    printf "  ${YELLOW}?${NC}  ${BOLD}%s${NC} [%s]: " "$label" "$default" >&2
  else
    printf "  ${YELLOW}?${NC}  ${BOLD}%s${NC}: " "$label" >&2
  fi
  read -r val
  printf '%s' "${val:-$default}"
}

confirm() {
  local msg="${1:-Continue?}" ans
  printf "  ${YELLOW}?${NC}  ${BOLD}%s${NC} [Y/n] " "$msg"
  read -r ans
  case "$ans" in [nN]*) return 1 ;; *) return 0 ;; esac
}

# ── live status helpers ───────────────────────────────────────────────────────
docker_ok()    { command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; }
navidrome_ok() { curl -sf --max-time 2 http://localhost:4533/ping >/dev/null 2>&1; }
syncthing_ok() { curl -sf --max-time 2 http://localhost:8384/ >/dev/null 2>&1; }



music_size() {
  if [ -d "$DEFAULT_OUTPUT_DIR" ]; then
    du -sh "$DEFAULT_OUTPUT_DIR" 2>/dev/null | awk '{print $1}'
  else
    echo "0B"
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
  arch="$(detect_arch)" || return 1
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
  printf "\n"
  printf "  ${CYAN}${BOLD}🌐 Domain Setup${NC}\n"
  printf "  ${DIM}────────────────────────────────────────────${NC}\n\n"

  info "Caddy needs a public domain for automatic HTTPS."
  info "A free DuckDNS subdomain works great:\n"
  printf "    ${BOLD}1.${NC} Go to ${BLUE}https://www.duckdns.org${NC} and log in\n"
  printf "    ${BOLD}2.${NC} Create a subdomain (e.g. ${BOLD}mymusic${NC})\n"
  printf "    ${BOLD}3.${NC} Point it to this server's public IP\n"
  printf "    ${BOLD}4.${NC} Enter your domain below\n\n"
  info "No domain yet? Press Enter to skip — Navidrome will"
  info "still work locally at http://localhost:4533\n"

  ensure_env_file

  local current_domain
  current_domain="$(grep '^DOMAIN=' "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo 'your-domain.duckdns.org')"

  local new_domain
  new_domain="$(prompt_val "Domain name (e.g. mymusic.duckdns.org)" "$current_domain")"

  if [ -z "$new_domain" ] || [ "$new_domain" = "your-domain.duckdns.org" ]; then
    warn "Keeping placeholder — HTTPS disabled until you set a real domain."
    new_domain="your-domain.duckdns.org"
  else
    ok "Domain → $new_domain"
  fi

  if grep -q '^DOMAIN=' "$PROJECT_ROOT/.env" 2>/dev/null; then
    sed -i "s|^DOMAIN=.*|DOMAIN=$new_domain|" "$PROJECT_ROOT/.env"
  else
    echo "DOMAIN=$new_domain" >> "$PROJECT_ROOT/.env"
  fi

  printf "\n"
  info "Syncthing uses your system UID/GID for file ownership."
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
  pause
}

# ── comprehensive onboarding wizard ──────────────────────────────────────────
run_onboarding() {
  local total_steps=5 step=0

  # ── Step 1: Welcome ──
  step=$((step + 1))
  clear || true
  printf "\n"
  printf "  ${CYAN}${BOLD}🎵 PrivateTunes — Setup Wizard${NC}  ${DIM}[${step}/${total_steps}]${NC}\n"
  printf "  ${DIM}────────────────────────────────────────────${NC}\n\n"
  printf "  Welcome! This wizard will walk you through:\n\n"
  printf "    ${GREEN}1.${NC} Configure your domain & .env\n"
  printf "    ${GREEN}2.${NC} Install spotiflac-cli (Spotify downloader)\n"
  printf "    ${GREEN}3.${NC} Create required directories\n"
  printf "    ${GREEN}4.${NC} Start the Docker stack\n"
  printf "    ${GREEN}5.${NC} Set up your Navidrome admin account\n\n"
  printf "  ${DIM}You can skip any step. Run this again anytime via [s].${NC}\n\n"

  if ! confirm "Ready to begin?"; then
    info "Skipped. Run [s] from the menu anytime."
    pause; return 0
  fi

  # ── Step 2: Domain + .env ──
  step=$((step + 1))
  clear || true
  printf "\n"
  printf "  ${CYAN}${BOLD}🌐 Domain & Environment${NC}  ${DIM}[${step}/${total_steps}]${NC}\n"
  printf "  ${DIM}────────────────────────────────────────────${NC}\n\n"

  ensure_env_file

  info "Caddy provides automatic HTTPS if you have a domain."
  info "Get a free one at ${BLUE}https://www.duckdns.org${NC}\n"
  info "No domain? Just press Enter to skip.\n"

  local current_domain new_domain
  current_domain="$(grep '^DOMAIN=' "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo 'your-domain.duckdns.org')"
  new_domain="$(prompt_val "Domain (e.g. mymusic.duckdns.org)" "$current_domain")"

  if [ -z "$new_domain" ] || [ "$new_domain" = "your-domain.duckdns.org" ]; then
    warn "No domain set — you can still use http://localhost:4533"
    new_domain="your-domain.duckdns.org"
  else
    ok "Domain → $new_domain"
  fi

  if grep -q '^DOMAIN=' "$PROJECT_ROOT/.env" 2>/dev/null; then
    sed -i "s|^DOMAIN=.*|DOMAIN=$new_domain|" "$PROJECT_ROOT/.env"
  else
    echo "DOMAIN=$new_domain" >> "$PROJECT_ROOT/.env"
  fi

  local uid_val gid_val
  uid_val="$(prompt_val "UID for Syncthing" "$(id -u)")"
  gid_val="$(prompt_val "GID for Syncthing" "$(id -g)")"

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
  ok ".env configured."

  # ── Step 3: spotiflac-cli ──
  step=$((step + 1))
  clear || true
  printf "\n"
  printf "  ${CYAN}${BOLD}📦 spotiflac-cli${NC}  ${DIM}[${step}/${total_steps}]${NC}\n"
  printf "  ${DIM}────────────────────────────────────────────${NC}\n\n"

  if [ -x "$SPOTIFLAC_CLI_BIN" ]; then
    ok "spotiflac-cli already installed."
    if confirm "Re-download / update?"; then
      install_spotiflac_cli
    fi
  else
    info "spotiflac-cli downloads music from Spotify as FLAC files."
    if confirm "Install spotiflac-cli now?"; then
      install_spotiflac_cli
    else
      warn "Skipped — you won't be able to download music until installed."
    fi
  fi

  # ── Step 4: Directories + Docker stack ──
  step=$((step + 1))
  clear || true
  printf "\n"
  printf "  ${CYAN}${BOLD}🐳 Docker Stack${NC}  ${DIM}[${step}/${total_steps}]${NC}\n"
  printf "  ${DIM}────────────────────────────────────────────${NC}\n\n"

  mkdir -p "$PROJECT_ROOT/music" "$PROJECT_ROOT/data/navidrome" "$PROJECT_ROOT/data/syncthing" "$BIN_DIR"
  ok "Directories created (music/, data/, bin/)."

  if ! docker_ok; then
    err "Docker not found. Install Docker first, then re-run setup."
    info "Install guide: https://docs.docker.com/engine/install/"
    info "Or run: ${BOLD}sudo $PROJECT_ROOT/scripts/setup.sh${NC}"
    pause
  else
    ok "Docker found: $(docker --version 2>/dev/null | head -c 50)"
    if confirm "Start the Docker stack now?"; then
      cd "$PROJECT_ROOT"
      docker compose up -d
      printf "\n"
      info "Waiting for Navidrome…"
      local retries=18
      until curl -sf --max-time 2 http://localhost:4533/ping >/dev/null 2>&1; do
        retries=$((retries - 1))
        if [ "$retries" -le 0 ]; then
          warn "Navidrome didn't respond in time."
          info "Check: docker compose logs navidrome"
          break
        fi
        printf "."
        sleep 10
      done
      printf "\n"
      if navidrome_ok; then
        ok "Stack is running!"
      fi
    else
      info "Skipped. Start later with menu option [4]."
    fi
  fi

  # ── Step 5: Navidrome admin ──
  step=$((step + 1))
  clear || true
  printf "\n"
  printf "  ${CYAN}${BOLD}👤 Navidrome Admin Account${NC}  ${DIM}[${step}/${total_steps}]${NC}\n"
  printf "  ${DIM}────────────────────────────────────────────${NC}\n\n"

  if navidrome_ok; then
    ok "Navidrome is running!\n"
    printf "  Open this URL in your browser to create your admin account:\n\n"
    printf "    ${BOLD}${GREEN}→ http://localhost:4533${NC}\n\n"
    local nd_domain
    nd_domain="$(grep '^DOMAIN=' "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2)"
    if [ -n "$nd_domain" ] && [ "$nd_domain" != "your-domain.duckdns.org" ]; then
      printf "    ${BOLD}${GREEN}→ https://${nd_domain}${NC}\n\n"
    fi
    printf "  ${DIM}The first user you create becomes the admin.${NC}\n"
    printf "  ${DIM}Choose a strong password — this controls your music library.${NC}\n"
  else
    warn "Navidrome is not running yet."
    info "Start the stack first (menu option [4]), then open:"
    printf "\n    ${BOLD}http://localhost:4533${NC}\n\n"
    info "The first user you create will be the admin."
  fi

  # ── Done ──
  printf "\n"
  printf "  ${CYAN}${BOLD}✅ Setup Complete!${NC}\n"
  printf "  ${DIM}────────────────────────────────────────────${NC}\n\n"
  printf "  ${BOLD}What's next:${NC}\n"
  printf "    • Create your admin account at ${BLUE}http://localhost:4533${NC}\n"
  printf "    • Download music with option ${YELLOW}2${NC} or ${YELLOW}b${NC}\n"
  printf "    • Connect Syncthing at ${BLUE}http://localhost:8384${NC}\n\n"
  printf "  ${DIM}PrivateTunes v${VERSION} • by @Paidguy${NC}\n"
  pause
}

# ── help screen ───────────────────────────────────────────────────────────────
show_help() {
  clear || true
  printf "\n"
  printf "  ${CYAN}${BOLD}❓ PrivateTunes — Help${NC}\n"
  printf "  ${DIM}────────────────────────────────────────────${NC}\n\n"

  printf "  Self-hosted music server: Navidrome + Caddy (HTTPS) + Syncthing.\n"
  printf "  Music downloaded via spotiflac-cli from Spotify URLs.\n\n"

  printf "  ${BOLD}${BLUE}COMMANDS${NC}\n"
  printf "  ${YELLOW}s${NC}  Setup wizard — domain, spotiflac-cli, Docker, Navidrome admin\n"
  printf "  ${YELLOW}1${NC}  Install/update spotiflac-cli binary\n"
  printf "  ${YELLOW}2${NC}  Download a Spotify track/album/playlist as FLAC\n"
  printf "  ${YELLOW}3${NC}  View metadata for a Spotify track\n"
  printf "  ${YELLOW}b${NC}  Batch download all URLs from links.txt\n"
  printf "  ${YELLOW}4${NC}  Start stack (docker compose up -d)\n"
  printf "  ${YELLOW}5${NC}  Stop stack (docker compose down)\n"
  printf "  ${YELLOW}6${NC}  Follow live container logs\n"
  printf "  ${YELLOW}7${NC}  Show container status + health checks\n"
  printf "  ${YELLOW}8${NC}  Restart only Navidrome\n"
  printf "  ${YELLOW}9${NC}  Domain setup wizard (set domain + UID/GID)\n"
  printf "  ${YELLOW}c${NC}  Backup .env, Caddyfile, docker-compose.yml\n"
  printf "  ${YELLOW}p${NC}  Show all paths + current .env\n\n"

  printf "  ${BOLD}${BLUE}PORTS${NC}\n"
  printf "  4533  Navidrome    8384  Syncthing    80/443  Caddy\n\n"

  printf "  ${BOLD}${BLUE}TROUBLESHOOTING${NC}\n"
  printf "  Music not scanning?  → Restart Navidrome [8] or scan in web UI\n"
  printf "  HTTPS broken?        → Check DOMAIN in .env, open 80/443, restart [4]\n"
  printf "  Container issues?    → View logs [6]\n\n"

  printf "  ${DIM}v${VERSION} • by @Paidguy • github.com/Paidguy/PrivateTunes${NC}\n"
  pause
}

# ── menu actions ──────────────────────────────────────────────────────────────
action_full_setup() {
  run_onboarding
}

action_install_or_update() {
  install_spotiflac_cli || { err "Failed to install spotiflac-cli."; }
  pause
}

action_download() {
  require_spotiflac_cli || return 0
  mkdir -p "$DEFAULT_OUTPUT_DIR"
  local url
  url="$(prompt "Spotify URL (track / album / playlist):")"
  if [ -z "$url" ]; then
    err "URL is required."; pause; return 0
  fi
  printf "\n"
  info "Downloading to: $DEFAULT_OUTPUT_DIR"
  if "$SPOTIFLAC_CLI_BIN" download "$url" --output "$DEFAULT_OUTPUT_DIR"; then
    ok "Download complete."
    # Trigger Navidrome scan if running
    if navidrome_ok; then
      info "Triggering Navidrome library scan…"
      curl -sf --max-time 5 -X POST http://localhost:4533/api/scan >/dev/null 2>&1 && \
        ok "Scan triggered." || info "Auto-scan not available — Navidrome will pick it up on next scheduled scan."
    fi
  else
    err "Download failed. Check the URL and try again."
  fi
  pause
}

action_batch_download() {
  require_spotiflac_cli || return 0
  mkdir -p "$DEFAULT_OUTPUT_DIR"

  if [ ! -f "$LINKS_FILE" ]; then
    err "links.txt not found at $LINKS_FILE"
    info "Create it with one Spotify URL per line."
    pause; return 0
  fi

  local count=0 total=0 failed=0
  # Count non-empty, non-comment lines
  total=$(grep -cE '^https?://' "$LINKS_FILE" 2>/dev/null || echo 0)

  if [ "$total" -eq 0 ]; then
    warn "No URLs found in links.txt."
    info "Add Spotify URLs (one per line) and try again."
    pause; return 0
  fi

  info "Found $total URL(s) in links.txt. Starting batch download…"
  printf "\n"

  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    count=$((count + 1))
    printf "\n${BOLD}[%d/%d]${NC} %s\n" "$count" "$total" "$line"
    if "$SPOTIFLAC_CLI_BIN" download "$line" --output "$DEFAULT_OUTPUT_DIR"; then
      ok "Done."
    else
      err "Failed: $line"
      failed=$((failed + 1))
    fi
  done < "$LINKS_FILE"

  printf "\n"
  ok "Batch complete: $((count - failed))/$count succeeded."
  [ "$failed" -gt 0 ] && warn "$failed download(s) failed."

  # Trigger scan
  if navidrome_ok; then
    info "Triggering Navidrome library scan…"
    curl -sf --max-time 5 -X POST http://localhost:4533/api/scan >/dev/null 2>&1 && \
      ok "Scan triggered." || info "Auto-scan not available."
  fi
  pause
}

action_metadata() {
  require_spotiflac_cli || return 0
  local url
  url="$(prompt "Spotify track URL:")"
  if [ -z "$url" ]; then
    err "URL is required."; pause; return 0
  fi
  printf "\n"
  "$SPOTIFLAC_CLI_BIN" metadata "$url" || err "Failed to fetch metadata."
  pause
}

action_stack_up() {
  require_docker || return 0
  ensure_env_file
  cd "$PROJECT_ROOT"
  info "Starting the stack…"
  docker compose up -d
  printf "\n"
  info "Waiting for Navidrome to respond…"
  local retries=19
  until curl -sf --max-time 2 http://localhost:4533/ping >/dev/null 2>&1; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      warn "Navidrome did not respond within ~3 minutes."
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
  require_docker || return 0
  cd "$PROJECT_ROOT"
  docker compose down
  ok "Stack stopped."
  pause
}

action_stack_logs() {
  require_docker || return 0
  info "Press Ctrl+C to stop following logs."
  cd "$PROJECT_ROOT"
  docker compose logs -f || true
}

action_stack_status() {
  require_docker || return 0
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
  printf "\n${BOLD}Disk usage${NC}\n"; hr
  printf "  Music library: %s\n" "$(music_size)"
  pause
}

action_stack_restart_navidrome() {
  require_docker || return 0
  cd "$PROJECT_ROOT"
  info "Restarting Navidrome…"
  docker compose restart navidrome
  ok "Navidrome restarted."
  pause
}

action_backup_config() {
  local ts backup_dir archive
  ts="$(date +%Y%m%d_%H%M%S)"
  backup_dir="$PROJECT_ROOT/backups"
  archive="$backup_dir/privatetunes-config-$ts.tar.gz"
  mkdir -p "$backup_dir"

  local files_to_backup=()
  [ -f "$PROJECT_ROOT/.env" ] && files_to_backup+=(".env")
  [ -f "$PROJECT_ROOT/Caddyfile" ] && files_to_backup+=("Caddyfile")
  [ -f "$PROJECT_ROOT/docker-compose.yml" ] && files_to_backup+=("docker-compose.yml")

  if [ ${#files_to_backup[@]} -eq 0 ]; then
    warn "No config files found to backup."
    pause; return 0
  fi

  cd "$PROJECT_ROOT"
  tar -czf "$archive" "${files_to_backup[@]}"
  ok "Config backed up → $archive"
  info "Files included: ${files_to_backup[*]}"
  pause
}

action_print_paths() {
  printf "\n${BOLD}Important paths${NC}\n"; hr
  printf "  Project root   : %s\n" "$PROJECT_ROOT"
  printf "  Music folder   : %s\n" "$DEFAULT_OUTPUT_DIR"
  printf "  Data folder    : %s\n" "$PROJECT_ROOT/data"
  printf "  spotiflac-cli  : %s\n" "$SPOTIFLAC_CLI_BIN"
  printf "  .env file      : %s\n" "$PROJECT_ROOT/.env"
  printf "  links.txt      : %s\n" "$LINKS_FILE"
  printf "  Music size     : %s\n" "$(music_size)"
  if [ -f "$PROJECT_ROOT/.env" ]; then
    printf "\n${BOLD}.env contents${NC}\n"; hr
    sed 's/^/  /' "$PROJECT_ROOT/.env"
  fi
  pause
}

# ── first-run onboarding check ────────────────────────────────────────────────
maybe_first_run_onboard() {
  local domain
  domain="$(get_env_val DOMAIN '')"
  if [ ! -f "$PROJECT_ROOT/.env" ] || [ -z "$domain" ] || [ "$domain" = "your-domain.duckdns.org" ]; then
    clear || true
    printf "\n"
    printf "  ${CYAN}${BOLD}🎵 Welcome to PrivateTunes!${NC}\n\n"
    printf "  Your private, self-hosted music server.\n"
    printf "  ${DIM}by @Paidguy • github.com/Paidguy/PrivateTunes${NC}\n\n"
    info "It looks like this is your first time here."
    printf "\n"
    if confirm "Run the setup wizard?"; then
      run_onboarding
    else
      ensure_env_file
      info "Skipped. Press [s] in the menu anytime."
      sleep 1
    fi
  fi
}

# ── env helpers ───────────────────────────────────────────────────────────────
get_env_val() {
  local key="$1" default="${2:-}"
  if [ -f "$PROJECT_ROOT/.env" ]; then
    local val
    val="$(grep "^${key}=" "$PROJECT_ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2-)"
    printf '%s' "${val:-$default}"
  else
    printf '%s' "$default"
  fi
}

set_env_val() {
  local key="$1" value="$2"
  ensure_env_file
  if grep -q "^${key}=" "$PROJECT_ROOT/.env" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=$value|" "$PROJECT_ROOT/.env"
  else
    echo "${key}=$value" >> "$PROJECT_ROOT/.env"
  fi
}

# ── main menu ─────────────────────────────────────────────────────────────────
draw_menu() {
  local d_stat=1 n_stat=1 s_stat=1
  docker_ok    && d_stat=0
  navidrome_ok && n_stat=0
  syncthing_ok && s_stat=0

  local domain lib_size
  domain="$(get_env_val DOMAIN 'not set')"
  [ "$domain" = "your-domain.duckdns.org" ] && domain="not configured"
  lib_size="$(music_size)"

  clear || true

  # ── header ──
  printf "\n"
  printf "  ${CYAN}${BOLD}🎵 PrivateTunes${NC}  ${DIM}v${VERSION}${NC}                 ${DIM}by @Paidguy${NC}\n"
  printf "  ${DIM}github.com/Paidguy/PrivateTunes${NC}\n"

  # ── status bar ──
  printf "\n  "
  if [ $d_stat -eq 0 ]; then printf "${GREEN}● Docker${NC}  "; else printf "${RED}○ Docker${NC}  "; fi
  if [ $n_stat -eq 0 ]; then printf "${GREEN}● Navidrome${NC}  "; else printf "${RED}○ Navidrome${NC}  "; fi
  if [ $s_stat -eq 0 ]; then printf "${GREEN}● Syncthing${NC}"; else printf "${RED}○ Syncthing${NC}"; fi
  printf "\n"
  printf "  ${DIM}Domain: ${NC}%-30s ${DIM}Library: ${NC}%s\n" "$domain" "$lib_size"

  # ── sections ──
  printf "\n  ${BOLD}${BLUE}SETUP${NC}\n"
  printf "    ${YELLOW}s${NC}  Full setup & onboarding       ${YELLOW}h${NC}  Help\n"

  printf "\n  ${BOLD}${BLUE}MUSIC${NC}\n"
  printf "    ${YELLOW}1${NC}  Install / update spotiflac     ${YELLOW}2${NC}  Download from Spotify URL\n"
  printf "    ${YELLOW}3${NC}  View track metadata            ${YELLOW}b${NC}  Batch download (links.txt)\n"

  printf "\n  ${BOLD}${BLUE}DOCKER${NC}\n"
  printf "    ${YELLOW}4${NC}  Start stack                    ${YELLOW}5${NC}  Stop stack\n"
  printf "    ${YELLOW}6${NC}  View logs                      ${YELLOW}7${NC}  Stack status\n"
  printf "    ${YELLOW}8${NC}  Restart Navidrome\n"

  printf "\n  ${BOLD}${BLUE}CONFIG${NC}\n"
  printf "    ${YELLOW}9${NC}  Domain wizard                  ${YELLOW}c${NC}  Backup config\n"
  printf "    ${YELLOW}p${NC}  Show paths / .env              ${YELLOW}0${NC}  Exit\n"
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
      b|B) action_batch_download ;;
      4)   action_stack_up ;;
      5)   action_stack_down ;;
      6)   action_stack_logs ;;
      7)   action_stack_status ;;
      8)   action_stack_restart_navidrome ;;
      9)   onboard_domain ;;
      c|C) action_backup_config ;;
      p|P) action_print_paths ;;
      0)
        printf "\n  ${DIM}Goodbye! — PrivateTunes by @Paidguy${NC}\n\n"
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
