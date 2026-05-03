#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# PrivateTunes — Download History System
# Persistent JSON database for tracking downloads across sessions.
# ─────────────────────────────────────────────────────────────────────────────

[ -n "${_PT_HISTORY_LOADED:-}" ] && return 0
_PT_HISTORY_LOADED=1

history_init() {
  mkdir -p "$HISTORY_DIR"
  [ -f "$HISTORY_FILE" ] || printf '{"version":1,"downloads":{}}' > "$HISTORY_FILE"
}

normalize_url() {
  local url="$1"
  url="${url%%\?*}"
  url="${url%%/}"
  url="$(printf '%s' "$url" | sed 's|^http://|https://|')"
  printf '%s' "$url"
}

extract_spotify_id() {
  local url="$1"
  url="$(normalize_url "$url")"
  local id
  id="$(printf '%s' "$url" | sed -n 's|.*open\.spotify\.com/\(track/[^/]*\).*|\1|p')"
  [ -z "$id" ] && id="$(printf '%s' "$url" | sed -n 's|.*open\.spotify\.com/\(album/[^/]*\).*|\1|p')"
  [ -z "$id" ] && id="$(printf '%s' "$url" | sed -n 's|.*open\.spotify\.com/\(playlist/[^/]*\).*|\1|p')"
  [ -z "$id" ] && id="$url"
  printf '%s' "$id"
}

history_check() {
  local url="$1"
  history_init
  local norm_url spotify_id
  norm_url="$(normalize_url "$url")"
  spotify_id="$(extract_spotify_id "$url")"

  if ensure_cmd jq; then
    local found
    found=$(jq -r --arg nurl "$norm_url" --arg sid "$spotify_id" \
      '.downloads | to_entries[] | select(.value.normalized_url == $nurl or .key == $sid) | .value.status' \
      "$HISTORY_FILE" 2>/dev/null | head -1)
    [ "$found" = "completed" ] && return 0
  else
    if grep -qF "\"$spotify_id\"" "$HISTORY_FILE" 2>/dev/null && \
       grep -A2 "\"$spotify_id\"" "$HISTORY_FILE" 2>/dev/null | grep -qF '"completed"'; then
      return 0
    fi
  fi
  return 1
}

history_record() {
  local url="$1" status="${2:-completed}"
  history_init
  local norm_url spotify_id ts
  norm_url="$(normalize_url "$url")"
  spotify_id="$(extract_spotify_id "$url")"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"

  if ensure_cmd jq; then
    local tmp_file="${HISTORY_FILE}.tmp.$$"
    jq --arg sid "$spotify_id" --arg nurl "$norm_url" --arg ourl "$url" \
       --arg st "$status" --arg ts "$ts" \
       '.downloads[$sid] = {
         "original_url": $ourl, "normalized_url": $nurl,
         "status": $st, "timestamp": $ts
       }' "$HISTORY_FILE" > "$tmp_file" 2>/dev/null && \
      mv -f "$tmp_file" "$HISTORY_FILE"
  else
    local log_file="${HISTORY_FILE%.json}.log"
    printf '%s\t%s\t%s\t%s\n' "$ts" "$status" "$spotify_id" "$norm_url" >> "$log_file"
  fi
}

history_check_log() {
  local url="$1"
  local log_file="${HISTORY_FILE%.json}.log"
  local spotify_id
  spotify_id="$(extract_spotify_id "$url")"
  if [ -f "$log_file" ]; then
    grep -qF "completed" "$log_file" 2>/dev/null && \
      grep -qF "$spotify_id" "$log_file" 2>/dev/null && return 0
  fi
  return 1
}

filesystem_check() {
  local url="$1"
  local url_type
  url_type="$(printf '%s' "$url" | sed -n 's|.*open\.spotify\.com/\([^/]*\)/.*|\1|p')"
  [ "$url_type" != "track" ] && return 1
  [ -x "$SPOTIFLAC_CLI_BIN" ] || return 1

  local meta_output
  meta_output=$("$SPOTIFLAC_CLI_BIN" metadata "$url" 2>/dev/null) || return 1
  local track_name track_artist
  track_name=$(printf '%s' "$meta_output" | grep -i '^Name:' | sed 's/^Name: *//' | head -1)
  track_artist=$(printf '%s' "$meta_output" | grep -i '^Artist:' | sed 's/^Artist: *//' | head -1)
  [ -z "$track_name" ] && return 1

  find "$DEFAULT_OUTPUT_DIR" -type f -iname "*.flac" 2>/dev/null | while IFS= read -r filepath; do
    local basename
    basename="$(basename "$filepath" .flac)"
    if printf '%s' "$basename" | grep -qi "$track_name" 2>/dev/null && \
       printf '%s' "$basename" | grep -qi "$track_artist" 2>/dev/null; then
      return 0
    fi
  done && return 0

  return 1
}

filesystem_check_by_name() {
  local track_name="$1" track_artist="$2"
  [ -z "$track_name" ] && return 1
  while IFS= read -r filepath; do
    local basename
    basename="$(basename "$filepath")"
    basename="${basename%.*}"
    if printf '%s' "$basename" | grep -qi "$track_name" 2>/dev/null; then
      if [ -z "$track_artist" ] || printf '%s' "$basename" | grep -qi "$track_artist" 2>/dev/null; then
        return 0
      fi
    fi
  done < <(find "$DEFAULT_OUTPUT_DIR" -type f \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.ogg' \) 2>/dev/null)
  return 1
}

history_stats() {
  history_init
  if ensure_cmd jq; then
    local total completed failed
    total=$(jq '.downloads | length' "$HISTORY_FILE" 2>/dev/null || echo 0)
    completed=$(jq '[.downloads[] | select(.status == "completed")] | length' "$HISTORY_FILE" 2>/dev/null || echo 0)
    failed=$(jq '[.downloads[] | select(.status == "failed")] | length' "$HISTORY_FILE" 2>/dev/null || echo 0)
    printf '%s %s %s' "$total" "$completed" "$failed"
  else
    local log_file="${HISTORY_FILE%.json}.log"
    if [ -f "$log_file" ]; then
      local total completed failed
      total=$(wc -l < "$log_file" 2>/dev/null || echo 0)
      completed=$(grep -c 'completed' "$log_file" 2>/dev/null || echo 0)
      failed=$(grep -c 'failed' "$log_file" 2>/dev/null || echo 0)
      printf '%s %s %s' "$total" "$completed" "$failed"
    else
      printf '0 0 0'
    fi
  fi
}

scan_existing_music() {
  history_init
  local scanned=0 added=0
  [ -d "$DEFAULT_OUTPUT_DIR" ] || { warn "Music directory not found: $DEFAULT_OUTPUT_DIR"; return 1; }

  spin_start "Scanning music directory for existing files…"

  while IFS= read -r filepath; do
    scanned=$((scanned + 1))
    local basename
    basename="$(basename "$filepath")"
    basename="${basename%.*}"
    [ -z "$basename" ] && continue

    local file_id
    file_id="file/$(printf '%s' "$basename" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g')"

    local already_tracked=false
    if ensure_cmd jq; then
      local found
      found=$(jq -r --arg fid "$file_id" '.downloads[$fid].status // empty' "$HISTORY_FILE" 2>/dev/null)
      [ -n "$found" ] && already_tracked=true
    fi

    if [ "$already_tracked" = false ]; then
      local ts
      ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
      if ensure_cmd jq; then
        local tmp_file="${HISTORY_FILE}.tmp.$$"
        jq --arg fid "$file_id" --arg bn "$basename" --arg fp "$filepath" --arg ts "$ts" \
           '.downloads[$fid] = {
             "original_url": ("filesystem://" + $fp),
             "normalized_url": ("filesystem://" + $bn),
             "status": "completed", "timestamp": $ts, "source": "filesystem_scan"
           }' "$HISTORY_FILE" > "$tmp_file" 2>/dev/null && \
          mv -f "$tmp_file" "$HISTORY_FILE"
      else
        local log_file="${HISTORY_FILE%.json}.log"
        printf '%s\t%s\t%s\t%s\n' "$ts" "completed" "$file_id" "filesystem://$basename" >> "$log_file"
      fi
      added=$((added + 1))
    fi
  done < <(find "$DEFAULT_OUTPUT_DIR" -type f \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.m4a' -o -iname '*.wav' \) 2>/dev/null)

  spin_stop ok "Scan complete: $scanned file(s) found, $added new entries added"
  return 0
}

maybe_auto_scan() {
  history_init
  local h_total=0
  ensure_cmd jq && h_total=$(jq '.downloads | length' "$HISTORY_FILE" 2>/dev/null || echo 0)

  if [ "$h_total" -eq 0 ]; then
    local file_count
    file_count=$(find "$DEFAULT_OUTPUT_DIR" -type f \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.m4a' -o -iname '*.wav' \) 2>/dev/null | wc -l)
    if [ "$file_count" -gt 0 ]; then
      printf "\n"
      info "Found $file_count existing music file(s) but download history is empty."
      if confirm "Scan existing files into history? (prevents re-downloading)"; then
        scan_existing_music
        pause
      fi
    fi
  fi
}

action_download_history() {
  history_init
  clear || true
  printf "\n"
  local w=60
  box_line $w
  box_row $((w - 2)) "  ${ACCENT}${BOLD}📋 Download History${NC}"
  box_end $w

  local stats h_total h_completed h_failed
  stats="$(history_stats)"
  h_total=$(echo "$stats" | awk '{print $1}')
  h_completed=$(echo "$stats" | awk '{print $2}')
  h_failed=$(echo "$stats" | awk '{print $3}')

  section_header "STATISTICS"
  printf "    Total tracked  : ${BOLD}%s${NC}\n" "$h_total"
  printf "    Completed      : ${GREEN}%s${NC}\n" "$h_completed"
  printf "    Failed         : ${RED}%s${NC}\n" "$h_failed"

  if ensure_cmd jq && [ -f "$HISTORY_FILE" ]; then
    local entry_count
    entry_count=$(jq '.downloads | length' "$HISTORY_FILE" 2>/dev/null || echo 0)
    if [ "$entry_count" -gt 0 ]; then
      section_header "RECENT DOWNLOADS"
      printf "    ${DIM}%-20s %-10s %s${NC}\n" "TIMESTAMP" "STATUS" "ID"
      jq -r '.downloads | to_entries | sort_by(.value.timestamp) | reverse | .[0:15][] |
        "    " + .value.timestamp + "  " +
        (if .value.status == "completed" then "✔ done" else "✘ fail" end) +
        "   " + .key' "$HISTORY_FILE" 2>/dev/null
    fi
  fi

  printf "\n  ${DIM}History file: %s${NC}\n" "$HISTORY_FILE"

  section_header "ACTIONS"
  menu_item "1" "Clear failed entries" "allow retry"
  menu_item "2" "Clear ALL history"
  menu_item "3" "Scan existing music files" "into history"
  menu_item "4" "Back to menu"
  menu_prompt
  local hchoice
  read -r hchoice
  case "$hchoice" in
    1)
      if ensure_cmd jq; then
        local tmp_file="${HISTORY_FILE}.tmp.$$"
        jq 'del(.downloads[] | select(.status == "failed"))' "$HISTORY_FILE" > "$tmp_file" 2>/dev/null && \
          mv -f "$tmp_file" "$HISTORY_FILE"
        ok "Failed entries cleared. They will be retried on next batch."
      fi
      pause ;;
    2)
      if confirm "Clear ALL download history? This cannot be undone."; then
        printf '{"version":1,"downloads":{}}' > "$HISTORY_FILE"
        local log_file="${HISTORY_FILE%.json}.log"
        [ -f "$log_file" ] && rm -f "$log_file"
        ok "Download history cleared."
      else
        info "Cancelled."
      fi
      pause ;;
    3) scan_existing_music; pause ;;
    *) ;;
  esac
}
