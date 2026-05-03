#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# PrivateTunes — Docker Stack Management
# Start, stop, restart, logs, and health checks for the Docker stack.
# ─────────────────────────────────────────────────────────────────────────────

[ -n "${_PT_DOCKER_LOADED:-}" ] && return 0
_PT_DOCKER_LOADED=1

# ── Status Helpers ────────────────────────────────────────────────────────────
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

require_docker() {
  if ! docker_ok; then
    err "Docker is not installed or the Compose plugin is missing."
    info "Fix it by running option [s] Full Setup."
    pause; return 1
  fi
}

# ── Actions ──────────────────────────────────────────────────────────────────
action_stack_up() {
  require_docker || return 0
  ensure_env_file
  cd "$PROJECT_ROOT"
  spin_start "Starting the Docker stack…"
  docker compose up -d 2>/dev/null
  spin_stop ok "Stack starting"

  info "Waiting for Navidrome…"
  local retries=18
  until curl -sf --max-time 2 http://localhost:4533/ping >/dev/null 2>&1; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      warn "Navidrome didn't respond within ~3 minutes."
      info "Check: docker compose logs navidrome"
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
  spin_start "Stopping the stack…"
  docker compose down 2>/dev/null
  spin_stop ok "Stack stopped"
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
  printf "\n"
  local w=60
  box_line $w
  box_row $((w - 2)) "  ${ACCENT}${BOLD}📊 Stack Status${NC}"
  box_end $w

  section_header "CONTAINERS"
  docker compose ps 2>/dev/null

  section_header "HEALTH CHECKS"
  if navidrome_ok; then ok "Navidrome  → http://localhost:4533"
  else err "Navidrome not responding on :4533"; fi
  if syncthing_ok; then ok "Syncthing  → http://localhost:8384"
  else warn "Syncthing not responding on :8384 (may be disabled)"; fi

  section_header "DISK USAGE"
  printf "    Music library: %s\n" "$(music_size)"
  pause
}

action_stack_restart_navidrome() {
  require_docker || return 0
  cd "$PROJECT_ROOT"
  spin_start "Restarting Navidrome…"
  docker compose restart navidrome 2>/dev/null
  spin_stop ok "Navidrome restarted"
  pause
}
