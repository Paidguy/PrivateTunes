#!/bin/bash

# Cloud Music Stack — Interactive Setup
# Created by @Paidguy  |  https://github.com/Paidguy/music

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"
SPOTIFLAC_CLI_BIN="$BIN_DIR/spotiflac-cli"

# ── colour palette ────────────────────────────────────────────────────────────
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
else
  BOLD=''; DIM=''; NC=''
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; MAGENTA=''
fi

# ── UI primitives ─────────────────────────────────────────────────────────────
hr()   { printf "${CYAN}%s${NC}\n" "──────────────────────────────────────────────────────────"; }
ok()   { printf " ${GREEN}${BOLD}✔${NC}  %s\n" "$*"; }
warn() { printf " ${YELLOW}${BOLD}⚠${NC}   %s\n" "$*"; }
err()  { printf " ${RED}${BOLD}✘${NC}  %s\n" "$*" >&2; }
info() { printf " ${CYAN}▸${NC}  %s\n" "$*"; }

step() {
  local n="$1" total="$2" label="$3"
  printf "\n${BOLD}${BLUE}[%s/%s]${NC} ${BOLD}%s${NC}\n" "$n" "$total" "$label"
  hr
}

# ask Y/n — default YES.  Returns 0 for yes, 1 for no.
confirm() {
  local msg="${1:-Continue?}"
  local ans
  printf " ${YELLOW}?${NC}  ${BOLD}%s${NC} [Y/n] " "$msg"
  read -r ans
  case "$ans" in
    [nN]*) return 1 ;;
    *)     return 0 ;;
  esac
}

# ask for a value with an optional default
prompt_val() {
  local label="$1" default="${2:-}"
  local val
  if [ -n "$default" ]; then
    printf " ${YELLOW}?${NC}  ${BOLD}%s${NC} [%s]: " "$label" "$default"
  else
    printf " ${YELLOW}?${NC}  ${BOLD}%s${NC}: " "$label"
  fi
  read -r val
  printf '%s' "${val:-$default}"
}

pause() { printf "\n"; read -r -p "  Press Enter to continue…" _; }

banner() {
  clear || true
  printf "${CYAN}"
  printf '╔══════════════════════════════════════════════════════════╗\n'
  printf '║                                                          ║\n'
  printf '║   🎵  Cloud Music Stack  —  Setup Wizard                ║\n'
  printf '║                                                          ║\n'
  printf '║   Built by %-45s║\n' "${MAGENTA}${BOLD}@Paidguy${CYAN}  https://github.com/Paidguy/music${NC}${CYAN}"
  printf '║                                                          ║\n'
  printf '╚══════════════════════════════════════════════════════════╝\n'
  printf "${NC}\n"
}

# ── system helpers ────────────────────────────────────────────────────────────
ensure_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_arch() {
  local arch; arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)   echo "amd64" ;;
    aarch64|arm64)  echo "arm64" ;;
    *) err "Unsupported architecture: $arch"; return 1 ;;
  esac
}

# ── installers ────────────────────────────────────────────────────────────────
install_docker() {
  info "Installing Docker Engine + Compose plugin via official apt repo…"

  sudo apt-get update -qq
  sudo apt-get install -y ca-certificates curl gnupg lsb-release

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -qq
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  sudo systemctl enable docker
  sudo systemctl start docker

  local calling_user; calling_user="${SUDO_USER:-$USER}"
  if [ -n "$calling_user" ] && [ "$calling_user" != "root" ]; then
    sudo usermod -aG docker "$calling_user"
    ok "Added '$calling_user' to the docker group."
    warn "You may need to log out/in (or run: newgrp docker) for this to take effect."
  fi

  ok "Docker: $(docker --version)"
  ok "Docker Compose: $(docker compose version)"
}

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
    exit 1
  fi

  chmod +x "$SPOTIFLAC_CLI_BIN"
  ok "spotiflac-cli installed → $SPOTIFLAC_CLI_BIN"
}

# ── domain onboarding wizard ──────────────────────────────────────────────────
onboard_domain() {
  printf "\n${BOLD}${BLUE}Domain Setup Wizard${NC}\n"
  hr
  printf "\n"
  info "Caddy (the reverse-proxy) needs a public domain name to get a"
  info "free HTTPS certificate automatically. You can use a free subdomain"
  info "from DuckDNS: https://www.duckdns.org"
  printf "\n"
  info "If you don't have a domain yet, you can still run the stack on your"
  info "local network — just leave the default value and change it later."
  printf "\n"

  local current_domain
  current_domain="$(grep '^DOMAIN' "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo 'your-domain.duckdns.org')"

  local new_domain
  new_domain="$(prompt_val "Your domain name (e.g. mymusic.duckdns.org)" "$current_domain")"

  if [ -z "$new_domain" ] || [ "$new_domain" = "your-domain.duckdns.org" ]; then
    warn "Using placeholder domain. HTTPS via Caddy won't work until you set a real domain."
    new_domain="your-domain.duckdns.org"
  else
    ok "Domain set to: $new_domain"
  fi

  # Write DOMAIN into .env
  if grep -q '^DOMAIN=' "$PROJECT_ROOT/.env" 2>/dev/null; then
    sed -i "s|^DOMAIN=.*|DOMAIN=$new_domain|" "$PROJECT_ROOT/.env"
  else
    echo "DOMAIN=$new_domain" >> "$PROJECT_ROOT/.env"
  fi

  # Also ask for UID/GID for Syncthing
  printf "\n"
  info "Syncthing needs your system user/group IDs (usually 1000)."
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

  ok ".env updated."
}

# ── main interactive setup flow ───────────────────────────────────────────────
main() {
  banner

  printf "${BOLD}Welcome to the Cloud Music Stack setup!${NC}\n"
  printf "This wizard will walk you through each step.\n"
  printf "You can skip any step you've already completed.\n\n"

  # ── Step 1: system packages ─────────────────────────────────────────────────
  step 1 6 "Base system packages (curl, git, gnupg, lsb-release)"
  if ensure_cmd apt-get; then
    if confirm "Install / refresh base packages?"; then
      sudo apt-get update -qq
      sudo apt-get install -y curl ca-certificates git gnupg lsb-release
      ok "Base packages ready."
    else
      info "Skipped. Make sure curl (or wget), ca-certificates, and git are available."
    fi
  else
    warn "apt-get not found — skipping. Ensure curl/wget, ca-certificates, and git are installed."
  fi

  # ── Step 2: Docker ──────────────────────────────────────────────────────────
  step 2 6 "Docker Engine + Docker Compose plugin"
  if ensure_cmd docker && docker compose version >/dev/null 2>&1; then
    ok "Docker already installed: $(docker --version)"
    ok "Docker Compose: $(docker compose version)"
    if confirm "Re-install / update Docker anyway?"; then
      install_docker
    fi
  else
    info "Docker is not installed."
    if confirm "Install Docker Engine + Compose plugin now?"; then
      install_docker
    else
      warn "Skipped. The stack will not start without Docker."
    fi
  fi

  # ── Step 3: directories ─────────────────────────────────────────────────────
  step 3 6 "Create required directories"
  mkdir -p \
    "$PROJECT_ROOT/music" \
    "$PROJECT_ROOT/data/navidrome" \
    "$PROJECT_ROOT/data/syncthing" \
    "$BIN_DIR"
  ok "Directories ready (music/, data/navidrome/, data/syncthing/, bin/)."

  # ── Step 4: spotiflac-cli ───────────────────────────────────────────────────
  step 4 6 "spotiflac-cli (Spotify → FLAC downloader)"
  if [ -x "$SPOTIFLAC_CLI_BIN" ]; then
    ok "spotiflac-cli already present."
    if confirm "Re-download / update spotiflac-cli?"; then
      install_spotiflac_cli
    fi
  else
    if confirm "Download and install spotiflac-cli?"; then
      install_spotiflac_cli
    else
      warn "Skipped. You won't be able to download music until it is installed."
    fi
  fi

  # ── Step 5: environment / domain ────────────────────────────────────────────
  step 5 6 "Environment configuration (.env) & domain setup"
  if [ ! -f "$PROJECT_ROOT/.env" ]; then
    cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
    ok "Created .env from .env.example."
  else
    ok ".env already exists."
  fi
  chmod +x "$PROJECT_ROOT/scripts/setup.sh" "$PROJECT_ROOT/scripts/cms.sh"

  if confirm "Run the domain & UID/GID setup wizard?"; then
    onboard_domain
  else
    info "Skipped. You can configure your domain later via: ./scripts/cms.sh → option 9"
  fi

  # ── Step 6: start the stack ─────────────────────────────────────────────────
  step 6 6 "Start the Docker stack"
  if ! ensure_cmd docker; then
    warn "Docker not found — cannot start the stack now."
  elif confirm "Start the Docker stack now? (docker compose up -d)"; then
    cd "$PROJECT_ROOT"
    docker compose up -d

    printf "\n"
    info "Waiting for Navidrome to be ready…"
    local retries=30
    until curl -sf http://localhost:4533/ping >/dev/null 2>&1; do
      retries=$((retries - 1))
      if [ "$retries" -le 0 ]; then
        warn "Navidrome did not respond after 5 minutes."
        info "Check logs with: docker compose logs navidrome"
        break
      fi
      printf "."
      sleep 10
    done
    printf "\n"

    if curl -sf http://localhost:4533/ping >/dev/null 2>&1; then
      ok "Navidrome is up → http://localhost:4533"
    fi
  else
    info "Skipped. Start later with: docker compose up -d"
  fi

  # ── Done ────────────────────────────────────────────────────────────────────
  local domain_val
  domain_val="$(grep '^DOMAIN' "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo 'your-domain.duckdns.org')"

  printf "\n${CYAN}"
  printf '╔══════════════════════════════════════════════════════════╗\n'
  printf '║                                                          ║\n'
  printf '║   ✅  Setup Complete!                                    ║\n'
  printf '║                                                          ║\n'
  printf "║   %-57s║\n" "Navidrome UI  →  http://localhost:4533"
  printf "║   %-57s║\n" "Syncthing UI  →  http://localhost:8384"
  printf "║   %-57s║\n" "Caddy HTTPS   →  https://$domain_val"
  printf '║                                                          ║\n'
  printf '║   Next step: run  ./scripts/cms.sh  to download music   ║\n'
  printf '║                                                          ║\n'
  printf '╚══════════════════════════════════════════════════════════╝\n'
  printf "${NC}\n"
}

main
