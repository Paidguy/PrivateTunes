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
  local norm_url spotify_id url_type
  norm_url="$(normalize_url "$url")"
  spotify_id="$(extract_spotify_id "$url")"
  url_type="$(printf '%s' "$url" | sed -n 's|.*open\.spotify\.com/\([^/]*\)/.*|\1|p')"

  # Check direct URL match
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

  # For albums/playlists, check if ALL tracks are already downloaded
  if [ "$url_type" = "album" ] || [ "$url_type" = "playlist" ]; then
    if check_all_tracks_in_history "$url"; then
      return 0
    fi
  fi

  return 1
}

# Check if all tracks in an album/playlist are already in history
check_all_tracks_in_history() {
  local url="$1"
  [ -x "$SPOTIFLAC_CLI_BIN" ] || return 1

  local metadata_json
  metadata_json=$("$SPOTIFLAC_CLI_BIN" "$url" --dump-json 2>/dev/null) || return 1

  if [ -z "$metadata_json" ]; then
    return 1
  fi

  if ensure_cmd jq; then
    # Get track IDs from metadata
    local track_ids
    track_ids=$(echo "$metadata_json" | jq -r '.items[]?.track.id // .items[].id // .tracks.items[]?.track.id // .tracks[].id // empty' 2>/dev/null)

    if [ -z "$track_ids" ]; then
      return 1
    fi

    local total=0 found=0
    while IFS= read -r track_id; do
      [ -z "$track_id" ] && continue
      total=$((total + 1))
      if grep -q "\"$track_id\"" "$HISTORY_FILE" 2>/dev/null && \
         grep -A2 "\"$track_id\"" "$HISTORY_FILE" 2>/dev/null | grep -q '"completed"'; then
        found=$((found + 1))
      fi
    done <<< "$track_ids"

    # If we have tracks and ALL of them are in history, consider it complete
    if [ "$total" -gt 0 ] && [ "$found" -eq "$total" ]; then
      return 0
    fi
  fi

  return 1
}

# Record all tracks from an album/playlist in history after successful download
record_playlist_tracks() {
  local url="$1"
  [ -x "$SPOTIFLAC_CLI_BIN" ] || return 1

  local metadata_json
  metadata_json=$("$SPOTIFLAC_CLI_BIN" "$url" --dump-json 2>/dev/null) || return 1

  if [ -z "$metadata_json" ]; then
    return 1
  fi

  if ensure_cmd jq; then
    # Get track IDs and their Spotify URLs from metadata
    local tracks_json
    tracks_json=$(echo "$metadata_json" | jq -r '.items[]?.track // .items[] // .tracks.items[]?.track // .tracks[]' 2>/dev/null)

    if [ -z "$tracks_json" ] || [ "$tracks_json" = "null" ]; then
      return 1
    fi

    echo "$tracks_json" | jq -r 'select(.id != null) | "track/\(.id)"' 2>/dev/null | while IFS= read -r track_spotify_id; do
      [ -z "$track_spotify_id" ] && continue
      # Record each track in history as completed
      history_record "https://open.spotify.com/$track_spotify_id" "completed"
    done
  fi
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

  # For single track, check if file exists by track name
  if [ "$url_type" = "track" ]; then
    [ -x "$SPOTIFLAC_CLI_BIN" ] || return 1

    local track_name track_artist
    track_name=$("$SPOTIFLAC_CLI_BIN" "$url" --print title 2>/dev/null)
    track_artist=$("$SPOTIFLAC_CLI_BIN" "$url" --print artist 2>/dev/null)
    [ -z "$track_name" ] && return 1

    if filesystem_check_by_name "$track_name" "$track_artist"; then
      return 0
    fi
    return 1
  fi

  # For album/playlist, check each track in the album/playlist
  if [ "$url_type" = "album" ] || [ "$url_type" = "playlist" ]; then
    [ -x "$SPOTIFLAC_CLI_BIN" ] || return 1

    # Get track list from metadata
    local metadata_json
    metadata_json=$("$SPOTIFLAC_CLI_BIN" "$url" --dump-json 2>/dev/null) || return 1

    if [ -z "$metadata_json" ]; then
      return 1
    fi

    # Check if any tracks exist on filesystem
    # For playlists, tracks are in items[].track.name
    # For albums, tracks are in items[].name
    local track_count=0
    local found_count=0

    if ensure_cmd jq; then
      # Try playlist format first
      track_count=$(echo "$metadata_json" | jq -r '.items[]?.track.name // .items[].name // empty' 2>/dev/null | wc -l)
      if [ "$track_count" -eq 0 ]; then
        # Try album format
        track_count=$(echo "$metadata_json" | jq -r '.tracks.items[]?.track.name // .tracks[]?.name // empty' 2>/dev/null | wc -l)
      fi

      if [ "$track_count" -gt 0 ]; then
        # Check if ANY track from the album/playlist exists on disk
        # If at least one exists, consider it "found" to avoid re-downloading
        local existing
        existing=$(echo "$metadata_json" | jq -r '.items[]?.track.name // .items[].name // .tracks.items[]?.track.name // .tracks[]?.name // empty' 2>/dev/null | while read -r track_name; do
          [ -z "$track_name" ] && continue
          if filesystem_check_by_name "$track_name" ""; then
            echo "found"
            break
          fi
        done)

        if [ -n "$existing" ]; then
          return 0
        fi
      fi
    fi
  fi

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
  menu_item "1" "Queue failed items for retry" "adds to links.txt"
  menu_item "2" "Clear ALL history"
  menu_item "3" "Scan existing music files" "into history"
  menu_item "4" "Back to menu"
  menu_prompt
  local hchoice
  read -r hchoice
  case "$hchoice" in
    1)
      if ensure_cmd jq; then
        local failed_count
        failed_count=$(jq '[.downloads[] | select(.status == "failed")] | length' "$HISTORY_FILE" 2>/dev/null || echo 0)
        if [ "$failed_count" -gt 0 ]; then
          jq -r '.downloads[] | select(.status == "failed") | .original_url' "$HISTORY_FILE" 2>/dev/null >> "$LINKS_FILE"
          
          local tmp_file="${HISTORY_FILE}.tmp.$$"
          jq 'del(.downloads[] | select(.status == "failed"))' "$HISTORY_FILE" > "$tmp_file" 2>/dev/null && \
            mv -f "$tmp_file" "$HISTORY_FILE"
          ok "$failed_count failed item(s) added to queue (links.txt) and cleared from history."
          info "Run 'Batch process queue' from the main menu to retry them."
        else
          info "No failed items found in history."
        fi
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
