#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# PrivateTunes — Configuration Management
# .env handling, domain wizard, backup, paths display.
# ─────────────────────────────────────────────────────────────────────────────

[ -n "${_PT_CONFIG_LOADED:-}" ] && return 0
_PT_CONFIG_LOADED=1

# ── .env Helpers ──────────────────────────────────────────────────────────────
ensure_env_file() {
  [ -f "$PROJECT_ROOT/.env" ] && return 0
  if [ -f "$PROJECT_ROOT/.env.example" ]; then
    cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
    ok "Created .env from .env.example."
  else
    warn ".env.example not found. Cannot create .env automatically."
  fi
}

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

# ── Domain Wizard ─────────────────────────────────────────────────────────────
onboard_domain() {
  clear || true
  printf "\n"
  printf "  ${ACCENT}${BOLD}🌐 Domain Setup${NC}\n"
  hr
  printf "\n"
  info "Caddy needs a public domain for automatic HTTPS."
  info "A free DuckDNS subdomain works great:\n"
  printf "    ${BOLD}1.${NC} Go to ${LBLUE}https://www.duckdns.org${NC} and log in\n"
  printf "    ${BOLD}2.${NC} Create a subdomain (e.g. ${BOLD}mymusic${NC})\n"
  printf "    ${BOLD}3.${NC} Point it to this server's public IP\n"
  printf "    ${BOLD}4.${NC} Enter your domain below\n\n"
  info "No domain yet? Press Enter to skip.\n"

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

  set_env_val "DOMAIN" "$new_domain"

  printf "\n"
  info "Syncthing uses your system UID/GID for file ownership."
  local uid_val gid_val
  uid_val="$(prompt_val "UID" "$(id -u)")"
  gid_val="$(prompt_val "GID" "$(id -g)")"
  set_env_val "UID" "$uid_val"
  set_env_val "GID" "$gid_val"

  printf "\n"
  ok ".env saved."
  pause
}

# ── Backup Config ─────────────────────────────────────────────────────────────
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

  spin_start "Backing up config…"
  cd "$PROJECT_ROOT"
  tar -czf "$archive" "${files_to_backup[@]}" 2>/dev/null
  spin_stop ok "Config backed up → $archive"
  info "Files included: ${files_to_backup[*]}"
  pause
}

# ── Show Paths ────────────────────────────────────────────────────────────────
action_print_paths() {
  printf "\n"
  local w=60
  box_line $w
  box_row $((w - 2)) "  ${ACCENT}${BOLD}📁 Paths & Environment${NC}"
  box_end $w

  section_header "PATHS"
  printf "    ${DIM}Project root${NC}   : %s\n" "$PROJECT_ROOT"
  printf "    ${DIM}Music folder${NC}   : %s\n" "$DEFAULT_OUTPUT_DIR"
  printf "    ${DIM}Data folder${NC}    : %s\n" "$PROJECT_ROOT/data"
  printf "    ${DIM}spotiflac-cli${NC}  : %s\n" "$SPOTIFLAC_CLI_BIN"
  printf "    ${DIM}.env file${NC}      : %s\n" "$PROJECT_ROOT/.env"
  printf "    ${DIM}links.txt${NC}      : %s\n" "$LINKS_FILE"
  printf "    ${DIM}History DB${NC}     : %s\n" "$HISTORY_FILE"

  section_header "STATS"
  printf "    Music size     : %s\n" "$(music_size)"
  local stats h_total h_completed h_failed
  stats="$(history_stats)"
  h_total=$(echo "$stats" | awk '{print $1}')
  h_completed=$(echo "$stats" | awk '{print $2}')
  h_failed=$(echo "$stats" | awk '{print $3}')
  printf "    Downloads      : %s total, %s completed, %s failed\n" "$h_total" "$h_completed" "$h_failed"

  if [ -f "$PROJECT_ROOT/.env" ]; then
    section_header ".ENV CONTENTS"
    sed 's/^/    /' "$PROJECT_ROOT/.env"
  fi
  pause
}
