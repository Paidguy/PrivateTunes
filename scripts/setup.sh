#!/bin/bash

set -euo pipefail

echo "🎵 Starting Music Stack Setup..."

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
      echo "❌ Unsupported architecture: $arch"
      return 1
      ;;
  esac
}

install_docker() {
  echo "🐳 Installing Docker Engine and Docker Compose plugin..."

  # Install prerequisite packages
  sudo apt-get update -qq
  sudo apt-get install -y ca-certificates curl gnupg lsb-release

  # Add Docker's official GPG key
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  # Add Docker's stable repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -qq
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  # Enable and start Docker daemon
  sudo systemctl enable docker
  sudo systemctl start docker

  # Add the calling user to the docker group so they can run docker without sudo
  local calling_user
  calling_user="${SUDO_USER:-$USER}"
  if [ -n "$calling_user" ] && [ "$calling_user" != "root" ]; then
    sudo usermod -aG docker "$calling_user"
    echo "✅ Added '$calling_user' to the docker group."
    echo "   ⚠️  You may need to log out and back in (or run: newgrp docker) for this to take effect."
  fi

  echo "✅ Docker installed: $(docker --version)"
  echo "✅ Docker Compose installed: $(docker compose version)"
}

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
    exit 1
  fi

  chmod +x "$SPOTIFLAC_CLI_BIN"
  echo "✅ spotiflac-cli installed to $SPOTIFLAC_CLI_BIN"
}

# ── Step 1: system packages ──────────────────────────────────────────────────
echo ""
echo "📦 Step 1/5 — Installing base system packages..."
if ensure_cmd apt-get; then
  sudo apt-get update -qq
  sudo apt-get install -y curl ca-certificates git gnupg lsb-release
else
  echo "⚠️  apt-get not found. Ensure curl (or wget), ca-certificates, and git are installed."
fi

# ── Step 2: Docker ───────────────────────────────────────────────────────────
echo ""
echo "🐳 Step 2/5 — Checking Docker..."
if ensure_cmd docker && docker compose version >/dev/null 2>&1; then
  echo "✅ Docker already installed: $(docker --version)"
  echo "✅ Docker Compose: $(docker compose version)"
else
  install_docker
fi

# ── Step 3: directories ──────────────────────────────────────────────────────
echo ""
echo "📁 Step 3/5 — Creating required directories..."
mkdir -p \
  "$PROJECT_ROOT/music" \
  "$PROJECT_ROOT/data/navidrome" \
  "$PROJECT_ROOT/data/syncthing" \
  "$BIN_DIR"
echo "✅ Directories ready."

# ── Step 4: spotiflac-cli ────────────────────────────────────────────────────
echo ""
echo "🎵 Step 4/5 — Installing spotiflac-cli..."
if [ -x "$SPOTIFLAC_CLI_BIN" ]; then
  echo "✅ spotiflac-cli already present at $SPOTIFLAC_CLI_BIN"
else
  install_spotiflac_cli
fi

# ── Step 5: .env + docker stack ─────────────────────────────────────────────
echo ""
echo "⚙️  Step 5/5 — Configuring environment and starting the stack..."

# Create .env from example if it doesn't exist
if [ ! -f "$PROJECT_ROOT/.env" ]; then
  cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
  echo "✅ Created .env from .env.example"
  echo "   Edit $PROJECT_ROOT/.env to set your DOMAIN before the stack starts if needed."
else
  echo "✅ .env already exists."
fi

# Make scripts executable
chmod +x "$PROJECT_ROOT/scripts/setup.sh" "$PROJECT_ROOT/scripts/cms.sh"

# Start the stack
echo ""
echo "🚀 Starting the Docker stack (docker compose up -d)..."
cd "$PROJECT_ROOT"
docker compose up -d

# Wait for Navidrome to become healthy
echo ""
echo "⏳ Waiting for Navidrome to be ready..."
RETRIES=30
until curl -sf http://localhost:4533/ping >/dev/null 2>&1; do
  RETRIES=$((RETRIES - 1))
  if [ "$RETRIES" -le 0 ]; then
    echo "⚠️  Navidrome did not respond after 5 minutes."
    echo "   Check logs with: docker compose logs navidrome"
    break
  fi
  sleep 10
done

if curl -sf http://localhost:4533/ping >/dev/null 2>&1; then
  echo "✅ Navidrome is up and responding at http://localhost:4533"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "================================================"
echo "✅  Setup Complete!"
echo "================================================"
echo "  Navidrome UI   : http://localhost:4533"
echo "  Syncthing UI   : http://localhost:8384"
DOMAIN_VAL="$(grep '^DOMAIN' "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo 'your-domain.duckdns.org')"
echo "  Caddy HTTPS    : https://$DOMAIN_VAL"
echo ""
echo "NEXT STEPS:"
echo "  1. Edit .env to set your DOMAIN if you haven't already:"
echo "     nano $PROJECT_ROOT/.env"
echo "  2. After changing DOMAIN, restart: docker compose up -d"
echo "  3. Download music via the interactive menu:"
echo "     ./scripts/cms.sh"
echo "================================================"
