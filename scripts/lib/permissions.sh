#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# PrivateTunes — Permission Handler
# Auto-checks and fixes execution permissions on every startup.
# Silent by default; verbose in DEBUG_MODE.
# ─────────────────────────────────────────────────────────────────────────────

[ -n "${_PT_PERMISSIONS_LOADED:-}" ] && return 0
_PT_PERMISSIONS_LOADED=1

# ── Auto-fix Permissions ─────────────────────────────────────────────────────
# Scans scripts/ and scripts/lib/ for .sh files without +x and fixes them.
# Idempotent — safe to call on every run.
ensure_script_permissions() {
  local fixed=0 checked=0
  local dirs_to_check=(
    "$PROJECT_ROOT/scripts"
    "$PROJECT_ROOT/scripts/lib"
  )

  for dir in "${dirs_to_check[@]}"; do
    [ -d "$dir" ] || continue
    for script in "$dir"/*.sh; do
      [ -f "$script" ] || continue
      checked=$((checked + 1))
      if [ ! -x "$script" ]; then
        chmod +x "$script" 2>/dev/null && {
          fixed=$((fixed + 1))
          debug_msg "Fixed permissions: $(basename "$script")"
        }
      fi
    done
  done

  # Also fix the main binary if present
  if [ -f "$SPOTIFLAC_CLI_BIN" ] && [ ! -x "$SPOTIFLAC_CLI_BIN" ]; then
    chmod +x "$SPOTIFLAC_CLI_BIN" 2>/dev/null && {
      fixed=$((fixed + 1))
      debug_msg "Fixed permissions: spotiflac-cli binary"
    }
  fi

  if [ "$fixed" -gt 0 ]; then
    debug_msg "Permission auto-fix: $fixed of $checked file(s) corrected"
  else
    debug_msg "Permissions OK: all $checked script(s) executable"
  fi

  return 0
}

# ── Verify Integrity ──────────────────────────────────────────────────────────
# Quick validation that critical scripts exist and are executable.
verify_script_integrity() {
  local issues=0

  if [ ! -f "$SCRIPT_PATH" ]; then
    err "Main script missing: $SCRIPT_PATH"
    issues=$((issues + 1))
  elif [ ! -x "$SCRIPT_PATH" ]; then
    warn "Main script not executable — fixing"
    chmod +x "$SCRIPT_PATH" 2>/dev/null || issues=$((issues + 1))
  fi

  return "$issues"
}
