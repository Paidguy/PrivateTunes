#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# PrivateTunes — API Resolver & Health Checker
# Smart API rotation with health tracking, fallback chains, and timeout control.
# ─────────────────────────────────────────────────────────────────────────────

[ -n "${_PT_API_RESOLVER_LOADED:-}" ] && return 0
_PT_API_RESOLVER_LOADED=1

# ── API Endpoint Registry ────────────────────────────────────────────────────
API_ENDPOINTS=(
  "tidal-primary|https://tidal-api.binimum.org|tidal"
  "tidal-lucida|https://lucida.to|tidal"
  "deezer-primary|https://deezer-api.binimum.org|deezer"
  "deezer-lucida|https://lucida.to|deezer"
)

declare -A API_HEALTH
declare -A API_FAIL_COUNT

API_HEALTH_CHECK_TIMEOUT=3
API_MAX_FAILS=3

_api_name()  { echo "$1" | cut -d'|' -f1; }
_api_url()   { echo "$1" | cut -d'|' -f2; }
_api_type()  { echo "$1" | cut -d'|' -f3; }

api_health_check() {
  local entry="$1"
  local name url
  name="$(_api_name "$entry")"
  url="$(_api_url "$entry")"
  debug_msg "Health check: $name ($url)"
  if curl -sf --max-time "$API_HEALTH_CHECK_TIMEOUT" \
       -o /dev/null "$url" 2>/dev/null; then
    API_HEALTH["$name"]=0
    API_FAIL_COUNT["$name"]=0
    return 0
  else
    API_HEALTH["$name"]=1
    API_FAIL_COUNT["$name"]=$(( ${API_FAIL_COUNT["$name"]:-0} + 1 ))
    return 1
  fi
}

api_mark_failed() {
  local name="$1"
  API_HEALTH["$name"]=1
  API_FAIL_COUNT["$name"]=$(( ${API_FAIL_COUNT["$name"]:-0} + 1 ))
}

api_mark_healthy() {
  local name="$1"
  API_HEALTH["$name"]=0
  API_FAIL_COUNT["$name"]=0
}

get_apis_by_type() {
  local api_type="$1"
  local healthy=() unhealthy=()
  for entry in "${API_ENDPOINTS[@]}"; do
    local name type
    name="$(_api_name "$entry")"
    type="$(_api_type "$entry")"
    [ "$type" != "$api_type" ] && continue
    local fails="${API_FAIL_COUNT[$name]:-0}"
    if [ "$fails" -lt "$API_MAX_FAILS" ]; then
      healthy+=("$entry")
    else
      unhealthy+=("$entry")
    fi
  done
  for e in "${healthy[@]}" "${unhealthy[@]}"; do echo "$e"; done
}

get_fallback_chain() {
  get_apis_by_type "tidal"
  get_apis_by_type "deezer"
}

api_preflight_check() {
  local total=0 healthy=0
  debug_msg "Running API preflight health check…"
  for entry in "${API_ENDPOINTS[@]}"; do
    total=$((total + 1))
    api_health_check "$entry" && healthy=$((healthy + 1))
  done
  debug_msg "API health: $healthy/$total endpoints responding"
  [ "$healthy" -eq 0 ] && {
    warn "No API endpoints are responding"
    return 1
  }
  return 0
}

resolve_track_source() {
  local api_name="$1" isrc="${2:-}"
  [ -n "$isrc" ] && printf "  ${GREEN}${ICO_OK} Matched via ISRC: %s${NC}\n" "$isrc"
  [ -n "$api_name" ] && printf "  ${GREEN}${ICO_OK} Source: %s${NC}\n" "$api_name"
}
