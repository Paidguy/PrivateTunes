#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# PrivateTunes — Download Engine
# Smart downloader with retry, API rotation, fallback, and queue management.
# ─────────────────────────────────────────────────────────────────────────────

[ -n "${_PT_DOWNLOADER_LOADED:-}" ] && return 0
_PT_DOWNLOADER_LOADED=1

MAX_RETRIES="${MAX_RETRIES:-3}"
BASE_BACKOFF="${BASE_BACKOFF:-5}"
RATE_LIMIT_WAIT="${RATE_LIMIT_WAIT:-60}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-300}"

# ── Download with Retry + API Rotation ────────────────────────────────────────
download_with_retry() {
  local url="$1" output_dir="$2"
  local attempt=0 wait_time=$BASE_BACKOFF
  local exit_code last_output

  while [ $attempt -lt $MAX_RETRIES ]; do
    attempt=$((attempt + 1))

    if [ $attempt -gt 1 ]; then
      debug_msg "Retry $attempt/$MAX_RETRIES in ${wait_time}s…"
      printf "  ${YELLOW}↻${NC}  Retry %d/%d in %ds…\n" "$attempt" "$MAX_RETRIES" "$wait_time"
      sleep $wait_time
      wait_time=$((wait_time * 3))
    fi

    # Capture output for error analysis
    last_output="$(timeout "$DOWNLOAD_TIMEOUT" \
      "$SPOTIFLAC_CLI_BIN" download "$url" --output "$output_dir" 2>&1)"
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
      return 0
    fi

    # Analyze failure for smart handling
    if echo "$last_output" | grep -qi "no such host\|dns\|resolve"; then
      debug_msg "DNS resolution failure detected"
    elif echo "$last_output" | grep -qi "502\|503\|504\|bad gateway"; then
      debug_msg "API gateway error detected"
    elif echo "$last_output" | grep -qi "deadline exceeded\|timeout"; then
      debug_msg "Timeout detected — extending wait"
      [ $wait_time -lt $RATE_LIMIT_WAIT ] && wait_time=$RATE_LIMIT_WAIT
    elif echo "$last_output" | grep -qi "rate.limit\|429\|too many"; then
      debug_msg "Rate limit detected — waiting ${RATE_LIMIT_WAIT}s"
      wait_time=$RATE_LIMIT_WAIT
    fi

    if [ $attempt -lt $MAX_RETRIES ]; then
      debug_msg "Attempt $attempt failed (exit: $exit_code)"
    fi
  done

  # Log the last error for debugging
  if [ -n "$last_output" ] && [ "${DEBUG_MODE:-0}" = "1" ]; then
    printf "  ${DIM}Last error output:\n"
    echo "$last_output" | tail -5 | sed 's/^/    /'
    printf "${NC}\n"
  fi

  return 1
}

# ── Graceful Track Skip ──────────────────────────────────────────────────────
skip_track() {
  local track_name="$1" reason="${2:-All APIs failed}"
  printf "  ${RED}${ICO_FAIL}${NC}  Track skipped: ${BOLD}%s${NC} ${DIM}(%s)${NC}\n" \
    "$track_name" "$reason"
}

# ── Install / Require spotiflac-cli ──────────────────────────────────────────
install_spotiflac_cli() {
  local arch asset url
  arch="$(detect_arch)" || return 1
  asset="spotiflac-cli-linux-$arch"
  url="https://github.com/Superredstone/spotiflac-cli/releases/download/v1.0.0/$asset"

  spin_start "Downloading spotiflac-cli ($asset)…"
  mkdir -p "$BIN_DIR"

  if ensure_cmd curl; then
    curl -fsSL "$url" -o "$SPOTIFLAC_CLI_BIN" 2>/dev/null
  elif ensure_cmd wget; then
    wget -q -O "$SPOTIFLAC_CLI_BIN" "$url" 2>/dev/null
  else
    spin_stop fail "Neither curl nor wget found"
    return 1
  fi

  if [ $? -eq 0 ] && [ -f "$SPOTIFLAC_CLI_BIN" ]; then
    chmod +x "$SPOTIFLAC_CLI_BIN"
    spin_stop ok "spotiflac-cli installed → $SPOTIFLAC_CLI_BIN"
  else
    spin_stop fail "Download failed"
    return 1
  fi
}

require_spotiflac_cli() {
  if [ -x "$SPOTIFLAC_CLI_BIN" ]; then return 0; fi
  info "spotiflac-cli not found — installing now…"
  install_spotiflac_cli
}

# ── Single Download Action ───────────────────────────────────────────────────
action_download() {
  require_spotiflac_cli || return 0
  mkdir -p "$DEFAULT_OUTPUT_DIR"
  local url
  url="$(prompt "Spotify URL (track / album / playlist):")"
  [ -z "$url" ] && { err "URL is required."; pause; return 0; }
  printf "\n"

  # Check download history
  if history_check "$url" || history_check_log "$url"; then
    local spotify_id
    spotify_id="$(extract_spotify_id "$url")"
    warn "Already downloaded: $spotify_id (from history)"
    if ! confirm "Re-download anyway?"; then
      info "Skipped."; pause; return 0
    fi
    info "Force re-downloading…"
  elif filesystem_check "$url"; then
    local spotify_id
    spotify_id="$(extract_spotify_id "$url")"
    warn "Already exists on disk: $spotify_id"
    if ! confirm "Re-download anyway?"; then
      history_record "$url" "completed"
      info "Skipped. Added to history."; pause; return 0
    fi
    info "Force re-downloading…"
  fi

  info "Downloading to: $DEFAULT_OUTPUT_DIR"
  if download_with_retry "$url" "$DEFAULT_OUTPUT_DIR"; then
    history_record "$url" "completed"
    ok "Download complete"
    if navidrome_ok; then
      info "Triggering Navidrome library scan…"
      curl -sf --max-time 5 -X POST http://localhost:4533/api/scan \
        >/dev/null 2>&1 && ok "Scan triggered." || \
        info "Auto-scan not available — Navidrome will pick it up."
    fi
  else
    history_record "$url" "failed"
    skip_track "$(extract_spotify_id "$url")" "Download failed after $MAX_RETRIES retries"
  fi
  pause
}

# ── Batch Download Action ────────────────────────────────────────────────────
action_batch_download() {
  require_spotiflac_cli || return 0
  mkdir -p "$DEFAULT_OUTPUT_DIR"

  if [ ! -f "$LINKS_FILE" ]; then
    err "links.txt not found at $LINKS_FILE"
    info "Create it with one Spotify URL per line."
    pause; return 0
  fi

  # Phase 1: Scan and filter
  history_init
  local total=0 skipped=0 pending=0 count=0 failed=0 succeeded=0
  local -a pending_urls=()

  total=$(grep -cE '^https?://' "$LINKS_FILE" 2>/dev/null || echo 0)
  [ "$total" -eq 0 ] && {
    warn "No URLs found in links.txt."
    info "Add Spotify URLs (one per line) and try again."
    pause; return 0
  }

  spin_start "Scanning $total URL(s) against download history…"

  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    if history_check "$line" || history_check_log "$line"; then
      skipped=$((skipped + 1))
    elif filesystem_check "$line"; then
      skipped=$((skipped + 1))
      history_record "$line" "completed"
    else
      pending_urls+=("$line")
      pending=$((pending + 1))
    fi
  done < "$LINKS_FILE"

  spin_stop ok "Scan complete"
  printf "\n"

  # Summary
  draw_summary_box "Batch Summary" \
    "Total in links.txt" "$total" \
    "Already completed" "${skipped} (skipped)" \
    "Remaining to fetch" "$pending"

  [ "$pending" -eq 0 ] && {
    printf "\n"
    ok "All URLs already downloaded! Nothing to do."
    info "To force re-download, clear history with [d]."
    pause; return 0
  }

  printf "\n"
  confirm "Proceed with $pending download(s)?" || { info "Cancelled."; pause; return 0; }

  # Phase 2: Download
  printf "\n"
  for url in "${pending_urls[@]}"; do
    count=$((count + 1))
    local sid
    sid="$(extract_spotify_id "$url")"
    batch_header "$count" "$pending" "$sid" "$url"

    if download_with_retry "$url" "$DEFAULT_OUTPUT_DIR"; then
      history_record "$url" "completed"
      succeeded=$((succeeded + 1))
      track_status "$count" "$pending" "$sid" "success"
    else
      history_record "$url" "failed"
      failed=$((failed + 1))
      track_status "$count" "$pending" "$sid" "failed"
    fi

    # Progress
    progress_bar "$count" "$pending" 30
    printf "\n"
  done

  # Phase 3: Results
  printf "\n"
  draw_summary_box "Batch Results" \
    "Succeeded" "$succeeded" \
    "Failed" "$failed" \
    "Skipped" "$skipped (from history)"

  [ "$failed" -gt 0 ] && {
    warn "$failed download(s) failed. Re-run batch to retry."
    info "Failed URLs are recorded — they will be retried next time."
  }

  if navidrome_ok && [ "$succeeded" -gt 0 ]; then
    info "Triggering Navidrome library scan…"
    curl -sf --max-time 5 -X POST http://localhost:4533/api/scan \
      >/dev/null 2>&1 && ok "Scan triggered." || info "Auto-scan not available."
  fi
  pause
}

# ── Install/Update Action ───────────────────────────────────────────────────
action_install_or_update() {
  install_spotiflac_cli || err "Failed to install spotiflac-cli."
  pause
}

# ── Metadata Action ──────────────────────────────────────────────────────────
action_metadata() {
  require_spotiflac_cli || return 0
  local url
  url="$(prompt "Spotify track URL:")"
  [ -z "$url" ] && { err "URL is required."; pause; return 0; }
  printf "\n"
  "$SPOTIFLAC_CLI_BIN" metadata "$url" || err "Failed to fetch metadata."
  pause
}
