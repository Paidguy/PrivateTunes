#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# PrivateTunes — Auto-Update System
# Git-based: fetch → compare → prompt → pull → permission-fix → restart
# ─────────────────────────────────────────────────────────────────────────────

[ -n "${_PT_UPDATER_LOADED:-}" ] && return 0
_PT_UPDATER_LOADED=1

UPDATE_CHECK_TIMEOUT="${UPDATE_CHECK_TIMEOUT:-5}"
REMOTE_NAME="${REMOTE_NAME:-origin}"
REMOTE_BRANCH="${REMOTE_BRANCH:-main}"

# ── Version Comparison (semver-aware) ─────────────────────────────────────────
# Returns 0 if v1 < v2 (update available), 1 otherwise
_version_lt() {
  local v1="$1" v2="$2"
  # Strip leading 'v' if present
  v1="${v1#v}"; v2="${v2#v}"

  local IFS='.'
  read -ra parts1 <<< "$v1"
  read -ra parts2 <<< "$v2"

  local i
  for i in 0 1 2; do
    local p1="${parts1[$i]:-0}" p2="${parts2[$i]:-0}"
    # Strip non-numeric suffixes
    p1="${p1%%[!0-9]*}"; p2="${p2%%[!0-9]*}"
    [ -z "$p1" ] && p1=0
    [ -z "$p2" ] && p2=0
    if [ "$p1" -lt "$p2" ] 2>/dev/null; then return 0; fi
    if [ "$p1" -gt "$p2" ] 2>/dev/null; then return 1; fi
  done
  return 1  # Equal
}

# ── Check for Updates ─────────────────────────────────────────────────────────
# Returns 0 if update is available and displays the update banner.
check_for_updates() {
  # Skip if not a git repo
  [ -d "$PROJECT_ROOT/.git" ] || return 1
  command -v git >/dev/null 2>&1 || return 1

  debug_msg "Checking for updates from $REMOTE_NAME/$REMOTE_BRANCH…"

  # Fetch with timeout (network-safe)
  if ! timeout "${UPDATE_CHECK_TIMEOUT}" \
       git -C "$PROJECT_ROOT" fetch "$REMOTE_NAME" "$REMOTE_BRANCH" \
       --quiet 2>/dev/null; then
    debug_msg "Update check: fetch failed (network issue?) — skipping"
    return 1
  fi

  local local_head remote_head
  local_head="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null)" || return 1
  remote_head="$(git -C "$PROJECT_ROOT" rev-parse \
    "$REMOTE_NAME/$REMOTE_BRANCH" 2>/dev/null)" || return 1

  if [ "$local_head" = "$remote_head" ]; then
    debug_msg "Already up to date (HEAD = $local_head)"
    return 1
  fi

  # Count commits behind
  local behind
  behind="$(git -C "$PROJECT_ROOT" rev-list --count \
    HEAD.."$REMOTE_NAME/$REMOTE_BRANCH" 2>/dev/null || echo 0)"
  [ "$behind" -eq 0 ] && return 1

  # Extract remote version string
  local remote_version
  remote_version="$(git -C "$PROJECT_ROOT" show \
    "$REMOTE_NAME/$REMOTE_BRANCH:scripts/privatetunes.sh" 2>/dev/null \
    | grep '^VERSION=' | head -1 | cut -d'"' -f2)" || remote_version="unknown"

  # Display update banner
  local w=60
  printf "\n"
  box_line $w
  box_row_empty $((w - 2))
  box_row_center $((w - 2)) "${YELLOW}${BOLD}${ICO_ROCKET}  Update Available${NC}"
  box_row_empty $((w - 2))
  box_divider $w
  box_row $((w - 2)) "  ${DIM}Installed${NC}    v${VERSION}"
  box_row $((w - 2)) "  ${ACCENT3}Latest${NC}      v${remote_version}  ${DIM}(${behind} commit(s) ahead)${NC}"
  box_row_empty $((w - 2))
  box_end $w

  return 0
}

# ── Perform Update ────────────────────────────────────────────────────────────
perform_update() {
  spin_start "Pulling latest changes…"

  # Stash local changes if any
  local has_changes=false
  if ! git -C "$PROJECT_ROOT" diff --quiet 2>/dev/null || \
     ! git -C "$PROJECT_ROOT" diff --cached --quiet 2>/dev/null; then
    has_changes=true
    spin_stop warn "Local changes detected — stashing"
    git -C "$PROJECT_ROOT" stash push \
      -m "privatetunes-auto-update-$(date +%s)" --quiet 2>/dev/null || {
      err "Failed to stash local changes. Update aborted."
      return 1
    }
    spin_start "Pulling latest changes…"
  fi

  # Pull
  if git -C "$PROJECT_ROOT" pull "$REMOTE_NAME" "$REMOTE_BRANCH" \
       --quiet 2>/dev/null; then
    spin_stop ok "Updated successfully!"

    # Re-apply permissions
    ensure_script_permissions
    ok "Permissions re-applied"

    # Restore stashed changes
    if [ "$has_changes" = true ]; then
      if git -C "$PROJECT_ROOT" stash pop --quiet 2>/dev/null; then
        ok "Local changes restored"
      else
        warn "Could not auto-restore local changes. Run: git stash pop"
      fi
    fi

    # Verify integrity
    verify_script_integrity

    info "Restarting CLI with updated version…"
    sleep 1
    exec "$SCRIPT_PATH" "$@"
  else
    spin_stop fail "Update failed — possible merge conflict"

    # Restore stash on failure
    if [ "$has_changes" = true ]; then
      git -C "$PROJECT_ROOT" stash pop --quiet 2>/dev/null || true
    fi
    warn "Update manually with: git pull"
    return 1
  fi
}

# ── Startup Update Check ─────────────────────────────────────────────────────
startup_update_check() {
  if check_for_updates; then
    printf "\n"
    printf "  ${ACCENT}${BOLD}[1]${NC} Update now     ${ACCENT}${BOLD}[2]${NC} Skip\n\n"
    printf "  ${ACCENT}▸${NC} "
    local ans
    read -r ans
    case "$ans" in
      2|[nNsS]*) info "Skipped. Update from the menu anytime [u]." ;;
      *)         perform_update ;;
    esac
    printf "\n"
  fi
}

# ── Manual Update Action ─────────────────────────────────────────────────────
action_check_update() {
  printf "\n"
  spin_start "Checking for updates…"
  sleep 1  # Allow spinner to be visible

  if check_for_updates; then
    spin_stop info "Update available"
    printf "\n  ${ACCENT}${BOLD}[1]${NC} Update now     ${ACCENT}${BOLD}[2]${NC} Skip\n\n"
    printf "  ${ACCENT}▸${NC} "
    local ans
    read -r ans
    case "$ans" in
      2|[nNsS]*) info "Update skipped." ;;
      *)         perform_update ;;
    esac
  else
    spin_stop ok "You're running the latest version (v${VERSION})"
  fi
  pause
}
