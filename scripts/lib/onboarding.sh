#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# PrivateTunes — Onboarding & Setup Wizard
# First-run detection, guided setup, and help screen.
# ─────────────────────────────────────────────────────────────────────────────

[ -n "${_PT_ONBOARDING_LOADED:-}" ] && return 0
_PT_ONBOARDING_LOADED=1

# ── Comprehensive Setup Wizard ────────────────────────────────────────────────
run_onboarding() {
  local total_steps=5 step=0

  # Step 1: Welcome
  step=$((step + 1))
  clear || true
  printf "\n"
  printf "  ${ACCENT}${BOLD}🎵 PrivateTunes — Setup Wizard${NC}  ${DIM}[${step}/${total_steps}]${NC}\n"
  hr
  printf "\n"
  printf "  Welcome! This wizard will walk you through:\n\n"
  printf "    ${GREEN}1.${NC} Configure your domain & .env\n"
  printf "    ${GREEN}2.${NC} Install spotiflac-cli (Spotify downloader)\n"
  printf "    ${GREEN}3.${NC} Create required directories\n"
  printf "    ${GREEN}4.${NC} Start the Docker stack\n"
  printf "    ${GREEN}5.${NC} Set up your Navidrome admin account\n\n"
  printf "  ${DIM}You can skip any step. Run this again anytime via [s].${NC}\n\n"

  confirm "Ready to begin?" || { info "Skipped. Run [s] from the menu anytime."; pause; return 0; }

  # Step 2: Domain + .env
  step=$((step + 1))
  clear || true
  printf "\n"
  printf "  ${ACCENT}${BOLD}🌐 Domain & Environment${NC}  ${DIM}[${step}/${total_steps}]${NC}\n"
  hr
  printf "\n"

  ensure_env_file
  info "Caddy provides automatic HTTPS if you have a domain."
  info "Get a free one at ${LBLUE}https://www.duckdns.org${NC}\n"
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
  set_env_val "DOMAIN" "$new_domain"

  local uid_val gid_val
  uid_val="$(prompt_val "UID for Syncthing" "$(id -u)")"
  gid_val="$(prompt_val "GID for Syncthing" "$(id -g)")"
  set_env_val "UID" "$uid_val"
  set_env_val "GID" "$gid_val"
  ok ".env configured."

  # Step 3: spotiflac-cli
  step=$((step + 1))
  clear || true
  printf "\n"
  printf "  ${ACCENT}${BOLD}📦 spotiflac-cli${NC}  ${DIM}[${step}/${total_steps}]${NC}\n"
  hr
  printf "\n"

  if [ -x "$SPOTIFLAC_CLI_BIN" ]; then
    ok "spotiflac-cli already installed."
    confirm "Re-download / update?" && install_spotiflac_cli
  else
    info "spotiflac-cli downloads music from Spotify as FLAC files."
    if confirm "Install spotiflac-cli now?"; then
      install_spotiflac_cli
    else
      warn "Skipped — you won't be able to download music until installed."
    fi
  fi

  # Step 4: Directories + Docker
  step=$((step + 1))
  clear || true
  printf "\n"
  printf "  ${ACCENT}${BOLD}🐳 Docker Stack${NC}  ${DIM}[${step}/${total_steps}]${NC}\n"
  hr
  printf "\n"

  mkdir -p "$PROJECT_ROOT/music" "$PROJECT_ROOT/data/navidrome" "$PROJECT_ROOT/data/syncthing" "$BIN_DIR"
  ok "Directories created (music/, data/, bin/)."

  if ! docker_ok; then
    err "Docker not found. Install Docker first, then re-run setup."
    info "Install guide: https://docs.docker.com/engine/install/"
    pause
  else
    ok "Docker found: $(docker --version 2>/dev/null | head -c 50)"
    if confirm "Start the Docker stack now?"; then
      cd "$PROJECT_ROOT"
      docker compose up -d
      printf "\n"
      info "Waiting for Navidrome…"
      local retries=18
      until navidrome_ok; do
        retries=$((retries - 1))
        [ "$retries" -le 0 ] && { warn "Navidrome didn't respond in time."; break; }
        printf "."; sleep 10
      done
      printf "\n"
      navidrome_ok && ok "Stack is running!"
    else
      info "Skipped. Start later with menu option [4]."
    fi
  fi

  # Step 5: Navidrome admin
  step=$((step + 1))
  clear || true
  printf "\n"
  printf "  ${ACCENT}${BOLD}👤 Navidrome Admin Account${NC}  ${DIM}[${step}/${total_steps}]${NC}\n"
  hr
  printf "\n"

  if navidrome_ok; then
    ok "Navidrome is running!\n"
    printf "  Open this URL in your browser to create your admin account:\n\n"
    printf "    ${BOLD}${GREEN}→ http://localhost:4533${NC}\n\n"
    local nd_domain
    nd_domain="$(get_env_val DOMAIN)"
    if [ -n "$nd_domain" ] && [ "$nd_domain" != "your-domain.duckdns.org" ]; then
      printf "    ${BOLD}${GREEN}→ https://${nd_domain}${NC}\n\n"
    fi
    printf "  ${DIM}The first user you create becomes the admin.${NC}\n"
  else
    warn "Navidrome is not running yet."
    info "Start the stack first (option [4]), then open:"
    printf "\n    ${BOLD}http://localhost:4533${NC}\n\n"
  fi

  # Done
  printf "\n"
  draw_summary_box "Setup Complete ✅" \
    "Admin account" "http://localhost:4533" \
    "Download music" "option 2 or b" \
    "Syncthing UI" "http://localhost:8384" \
    "Version" "v${VERSION} by @Paidguy"
  pause
}

# ── First-Run Check ──────────────────────────────────────────────────────────
maybe_first_run_onboard() {
  local domain
  domain="$(get_env_val DOMAIN '')"
  if [ ! -f "$PROJECT_ROOT/.env" ] || [ -z "$domain" ] || [ "$domain" = "your-domain.duckdns.org" ]; then
    clear || true
    printf "\n"
    local w=60
    box_line $w
    box_row_empty $((w - 2))
    box_row_center $((w - 2)) "${ACCENT}${BOLD}♫  Welcome to PrivateTunes!${NC}"
    box_row_center $((w - 2)) "${DIM}Your private, self-hosted music server${NC}"
    box_row_empty $((w - 2))
    box_row_center $((w - 2)) "${DIM}by @Paidguy • github.com/Paidguy/PrivateTunes${NC}"
    box_end $w
    printf "\n"
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

# ── Help Screen ──────────────────────────────────────────────────────────────
show_help() {
  clear || true
  printf "\n"
  local w=60
  box_line $w
  box_row $((w - 2)) "  ${ACCENT}${BOLD}❓ PrivateTunes — Help${NC}"
  box_row_empty $((w - 2))
  box_row $((w - 2)) "  Self-hosted music server powered by:"
  box_row $((w - 2)) "  Navidrome + Caddy (HTTPS) + Syncthing"
  box_row $((w - 2)) "  Music via spotiflac-cli from Spotify URLs."
  box_end $w

  section_header "COMMANDS"
  menu_item_pair "s" "Setup wizard" "h" "Help & docs"
  menu_item_pair "u" "Check for updates" "1" "Install spotiflac"
  menu_item_pair "2" "Download music" "3" "Track metadata"
  menu_item_pair "b" "Batch download" "d" "Download history"
  menu_item_pair "4" "Start stack" "5" "Stop stack"
  menu_item_pair "6" "View logs" "7" "Stack status"
  menu_item_pair "8" "Restart Navidrome" "9" "Domain wizard"
  menu_item_pair "c" "Backup config" "p" "Show paths"

  section_header "PORTS"
  printf "    ${WHITE}4533${NC}  Navidrome       ${WHITE}8384${NC}  Syncthing       ${WHITE}80/443${NC}  Caddy\n"

  section_header "TROUBLESHOOTING"
  printf "    Music not scanning?  ${DIM}→${NC} Restart Navidrome ${WHITE}[8]${NC}\n"
  printf "    HTTPS broken?        ${DIM}→${NC} Check DOMAIN in .env\n"
  printf "    Container issues?    ${DIM}→${NC} View logs ${WHITE}[6]${NC}\n"

  section_header "FLAGS"
  printf "    ${WHITE}--debug${NC}   Enable verbose debug logging\n"

  printf "\n  ${DIM}v${VERSION} • by @Paidguy • github.com/Paidguy/PrivateTunes${NC}\n"
  pause
}
