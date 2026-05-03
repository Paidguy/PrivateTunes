#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# PrivateTunes — UI Rendering Module
# Premium CLI interface: colors, box-drawing, spinners, progress, badges
# ─────────────────────────────────────────────────────────────────────────────

# Guard against double-sourcing
[ -n "${_PT_UI_LOADED:-}" ] && return 0
_PT_UI_LOADED=1

# ── Colour Palette ────────────────────────────────────────────────────────────
# Detects terminal capability and sets ANSI escape codes accordingly
_ui_init_colors() {
  if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    # Text styles
    BOLD='\033[1m';  DIM='\033[2m';  ITALIC='\033[3m'
    UNDERLINE='\033[4m';  BLINK='\033[5m';  NC='\033[0m'

    # Standard colors
    RED='\033[0;31m';     LRED='\033[1;31m'
    GREEN='\033[0;32m';   LGREEN='\033[1;32m'
    YELLOW='\033[1;33m';  LYELLOW='\033[0;33m'
    BLUE='\033[0;34m';    LBLUE='\033[1;34m'
    MAGENTA='\033[0;35m'; LMAGENTA='\033[1;35m'
    CYAN='\033[0;36m';    LCYAN='\033[1;36m'
    WHITE='\033[1;37m';   GRAY='\033[0;90m'
    LGRAY='\033[0;37m'

    # 256-color accents (premium feel)
    ACCENT='\033[38;5;75m'      # Soft blue
    ACCENT2='\033[38;5;183m'    # Lavender
    ACCENT3='\033[38;5;114m'    # Mint green
    ACCENT4='\033[38;5;209m'    # Coral/salmon
    ACCENT5='\033[38;5;228m'    # Pale gold
    DIMACCENT='\033[38;5;240m'  # Dark gray

    # Background colors
    BG_CYAN='\033[46m';   BG_BLUE='\033[44m'
    BG_GREEN='\033[42m';  BG_RED='\033[41m'
    BG_GRAY='\033[48;5;236m'
  else
    BOLD=''; DIM=''; ITALIC=''; UNDERLINE=''; BLINK=''; NC=''
    RED=''; LRED=''; GREEN=''; LGREEN=''; YELLOW=''; LYELLOW=''
    BLUE=''; LBLUE=''; MAGENTA=''; LMAGENTA=''; CYAN=''; LCYAN=''
    WHITE=''; GRAY=''; LGRAY=''
    ACCENT=''; ACCENT2=''; ACCENT3=''; ACCENT4=''; ACCENT5=''; DIMACCENT=''
    BG_CYAN=''; BG_BLUE=''; BG_GREEN=''; BG_RED=''; BG_GRAY=''
  fi
}

_ui_init_colors

# ── Box-Drawing Characters ────────────────────────────────────────────────────
B_TL='╭'; B_TR='╮'; B_BL='╰'; B_BR='╯'; B_H='─'; B_V='│'
B_DTL='╔'; B_DTR='╗'; B_DBL='╚'; B_DBR='╝'; B_DH='═'; B_DV='║'

# ── Spinner Frames ────────────────────────────────────────────────────────────
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_PID=""

# ── Unicode Icons ─────────────────────────────────────────────────────────────
ICO_OK='✔';  ICO_FAIL='✘';  ICO_WARN='⚠';  ICO_INFO='▸'
ICO_SKIP='⊘';  ICO_ARROW='→';  ICO_MUSIC='♫';  ICO_GEAR='⚙'
ICO_LOCK='🔒'; ICO_UP='⬆';  ICO_DOWN='⬇';  ICO_ROCKET='🚀'
ICO_FIRE='🔥'; ICO_STAR='★';  ICO_DOT='●';   ICO_CIRCLE='○'
ICO_CHECK='☑'; ICO_CROSS='☒'; ICO_DASH='─';  ICO_PIPE='│'

# ── Message Primitives ────────────────────────────────────────────────────────
ok()   { printf "  ${GREEN}${BOLD} ${ICO_OK} ${NC}  %s\n" "$*"; }
warn() { printf "  ${YELLOW}${BOLD} ${ICO_WARN} ${NC}  %s\n" "$*"; }
err()  { printf "  ${RED}${BOLD} ${ICO_FAIL} ${NC}  %s\n" "$*" >&2; }
info() { printf "  ${ACCENT} ${ICO_INFO} ${NC}  %s\n" "$*"; }
dim()  { printf "  ${DIM}    %s${NC}\n" "$*"; }
debug_msg() {
  [ "${DEBUG_MODE:-0}" = "1" ] && printf "  ${GRAY}${DIM} ◦ %s${NC}\n" "$*"
}

# ── Box Drawing ───────────────────────────────────────────────────────────────
box_line() {
  local width="${1:-60}"
  printf "  ${DIMACCENT}${B_TL}"
  printf "%0.s${B_H}" $(seq 1 "$width")
  printf "${B_TR}${NC}\n"
}

box_end() {
  local width="${1:-60}"
  printf "  ${DIMACCENT}${B_BL}"
  printf "%0.s${B_H}" $(seq 1 "$width")
  printf "${B_BR}${NC}\n"
}

box_row() {
  local width="${1:-58}" text="$2"
  printf "  ${DIMACCENT}${B_V}${NC} %-${width}b ${DIMACCENT}${B_V}${NC}\n" "$text"
}

box_row_center() {
  local width="${1:-58}" text="$2"
  local text_plain
  text_plain="$(printf '%b' "$text" | sed 's/\x1b\[[0-9;]*m//g')"
  local text_len=${#text_plain}
  local pad_total=$((width - text_len))
  local pad_left=$((pad_total / 2))
  local pad_right=$((pad_total - pad_left))
  printf "  ${DIMACCENT}${B_V}${NC}%${pad_left}s%b%${pad_right}s${DIMACCENT}${B_V}${NC}\n" "" "$text" ""
}

box_row_empty() {
  local width="${1:-58}"
  printf "  ${DIMACCENT}${B_V}${NC} %-${width}s ${DIMACCENT}${B_V}${NC}\n" ""
}

box_divider() {
  local width="${1:-60}"
  printf "  ${DIMACCENT}├"
  printf "%0.s─" $(seq 1 "$width")
  printf "┤${NC}\n"
}

# ── Section Headers ───────────────────────────────────────────────────────────
section_header() {
  local label="$1"
  printf "\n  ${BOLD}${ACCENT}─── %s ${NC}" "$label"
  local label_len=${#label}
  local remaining=$((52 - label_len))
  [ "$remaining" -gt 0 ] && printf "${DIMACCENT}%0.s─${NC}" $(seq 1 "$remaining")
  printf "\n"
}

hr() {
  printf "  ${DIMACCENT}────────────────────────────────────────────────────────────${NC}\n"
}

hr_thin() {
  printf "  ${GRAY}· · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·${NC}\n"
}

# ── Branded Header ────────────────────────────────────────────────────────────
draw_header() {
  local w=60
  box_line $w
  box_row_empty $((w - 2))
  box_row_center $((w - 2)) "${ACCENT}${BOLD}♫  P R I V A T E T U N E S${NC}"
  box_row_center $((w - 2)) "${DIM}self-hosted music · beautifully simple${NC}"
  box_row_empty $((w - 2))
  box_row $((w - 2)) "  ${DIM}v${VERSION}${NC}                                ${DIM}by @Paidguy${NC}"
  box_end $w
}

# ── Status Badges ─────────────────────────────────────────────────────────────
badge_ok()   { printf "${GREEN}${ICO_DOT}${NC}"; }
badge_fail() { printf "${RED}${ICO_CIRCLE}${NC}"; }
badge_warn() { printf "${YELLOW}${ICO_DOT}${NC}"; }

status_line() {
  local label="$1" ok="$2"
  if [ "$ok" = "0" ]; then
    printf " ${GREEN}${ICO_DOT}${NC} ${WHITE}%s${NC}" "$label"
  else
    printf " ${RED}${ICO_CIRCLE}${NC} ${GRAY}%s${NC}" "$label"
  fi
}

# ── Service Status Bar ────────────────────────────────────────────────────────
draw_status_bar() {
  local d_stat="$1" n_stat="$2" s_stat="$3"
  local domain="$4" lib_size="$5" tracked="$6" failed="${7:-0}"

  printf "\n  "
  status_line "Docker" "$d_stat"
  printf "   "
  status_line "Navidrome" "$n_stat"
  printf "   "
  status_line "Syncthing" "$s_stat"
  printf "\n"

  printf "  ${GRAY}domain${NC}  %-20s" "$domain"
  printf " ${GRAY}library${NC}  %-8s" "$lib_size"
  printf " ${GRAY}tracked${NC}  %s" "$tracked"
  [ "$failed" -gt 0 ] 2>/dev/null && printf " ${RED}(%s failed)${NC}" "$failed"
  printf "\n"
}

# ── Menu Renderer ─────────────────────────────────────────────────────────────
menu_item() {
  local key="$1" label="$2" desc="${3:-}"
  if [ -n "$desc" ]; then
    printf "    ${ACCENT}${BOLD}%s${NC}  %-26s ${DIM}%s${NC}\n" "$key" "$label" "$desc"
  else
    printf "    ${ACCENT}${BOLD}%s${NC}  %s\n" "$key" "$label"
  fi
}

menu_item_pair() {
  local k1="$1" l1="$2" k2="$3" l2="$4"
  printf "    ${ACCENT}${BOLD}%s${NC}  %-28s ${ACCENT}${BOLD}%s${NC}  %s\n" "$k1" "$l1" "$k2" "$l2"
}

# ── Prompt Helpers ────────────────────────────────────────────────────────────
prompt() {
  local label="${1:?label required}" val
  printf "  ${ACCENT5}?${NC}  ${BOLD}%s${NC} " "$label" >&2
  read -r val
  printf '%s' "$val"
}

prompt_val() {
  local label="$1" default="${2:-}" val
  if [ -n "$default" ]; then
    printf "  ${ACCENT5}?${NC}  ${BOLD}%s${NC} [%s]: " "$label" "$default" >&2
  else
    printf "  ${ACCENT5}?${NC}  ${BOLD}%s${NC}: " "$label" >&2
  fi
  read -r val
  printf '%s' "${val:-$default}"
}

confirm() {
  local msg="${1:-Continue?}" ans
  printf "  ${ACCENT5}?${NC}  ${BOLD}%s${NC} [Y/n] " "$msg"
  read -r ans
  case "$ans" in [nN]*) return 1 ;; *) return 0 ;; esac
}

menu_prompt() {
  printf "\n  ${ACCENT}▸${NC} ${BOLD}Select:${NC} "
}

pause() {
  printf "\n"
  read -r -p "  Press Enter to continue… " _
}

# ── Spinner ───────────────────────────────────────────────────────────────────
# Start a background spinner with a message
spin_start() {
  local msg="${1:-Working…}"
  SPINNER_MSG="$msg"
  (
    local i=0
    while true; do
      local frame="${SPINNER_FRAMES[$((i % ${#SPINNER_FRAMES[@]}))]}"
      printf "\r  ${ACCENT}%s${NC}  %s " "$frame" "$msg" >&2
      i=$((i + 1))
      sleep 0.1
    done
  ) &
  SPINNER_PID=$!
  disown "$SPINNER_PID" 2>/dev/null
}

# Stop the spinner and show result
spin_stop() {
  local status="${1:-ok}" msg="${2:-$SPINNER_MSG}"
  if [ -n "$SPINNER_PID" ]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null
    SPINNER_PID=""
  fi
  printf "\r\033[2K" >&2  # Clear the spinner line
  case "$status" in
    ok)   ok "$msg" ;;
    fail) err "$msg" ;;
    warn) warn "$msg" ;;
    info) info "$msg" ;;
    *)    printf "  %s\n" "$msg" ;;
  esac
}

# ── Progress Bar ──────────────────────────────────────────────────────────────
# Renders: [████████░░░░░░░░] 12/470
progress_bar() {
  local current="$1" total="$2" width="${3:-30}" label="${4:-}"
  local pct=0 filled=0 empty=0

  if [ "$total" -gt 0 ]; then
    pct=$((current * 100 / total))
    filled=$((current * width / total))
  fi
  empty=$((width - filled))

  local bar=""
  [ "$filled" -gt 0 ] && bar="$(printf "%0.s█" $(seq 1 "$filled"))"
  [ "$empty" -gt 0 ]  && bar="${bar}$(printf "%0.s░" $(seq 1 "$empty"))"

  if [ -n "$label" ]; then
    printf "\r  ${ACCENT}[${NC}%s${ACCENT}]${NC} ${BOLD}%d/%d${NC}  %s" "$bar" "$current" "$total" "$label"
  else
    printf "\r  ${ACCENT}[${NC}%s${ACCENT}]${NC} ${BOLD}%d/%d${NC} (%d%%)" "$bar" "$current" "$total" "$pct"
  fi
}

# ── Track Status Line ─────────────────────────────────────────────────────────
track_status() {
  local index="$1" total="$2" name="$3" status="$4"
  local icon color status_text

  case "$status" in
    downloading)
      icon="⏳"; color="$ACCENT"; status_text="Downloading…"
      ;;
    success)
      icon="$ICO_OK"; color="$GREEN"; status_text="Complete"
      ;;
    failed)
      icon="$ICO_FAIL"; color="$RED"; status_text="Failed"
      ;;
    skipped)
      icon="$ICO_SKIP"; color="$GRAY"; status_text="Skipped"
      ;;
    retrying)
      icon="↻"; color="$YELLOW"; status_text="Retrying…"
      ;;
    *)
      icon="·"; color="$DIM"; status_text="$status"
      ;;
  esac

  printf "  ${BOLD}[%d/%d]${NC}  ${color}%s${NC}  %-35s ${color}%s${NC}\n" \
    "$index" "$total" "$icon" "$name" "$status_text"
}

# ── Batch Header ──────────────────────────────────────────────────────────────
batch_header() {
  local current="$1" total="$2" track_id="$3" url="$4"
  printf "\n  ${ACCENT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "  ${BOLD}[%d/%d]${NC}  %s\n" "$current" "$total" "$track_id"
  printf "  ${DIM}%s${NC}\n" "$url"
}

# ── Summary Box ───────────────────────────────────────────────────────────────
draw_summary_box() {
  local title="$1"
  shift
  local w=60

  box_line $w
  box_row $((w - 2)) "  ${ACCENT}${BOLD}${title}${NC}"
  box_divider $w

  while [ $# -ge 2 ]; do
    local label="$1" value="$2"
    shift 2
    box_row $((w - 2)) "  ${DIM}${label}${NC}  ${BOLD}${value}${NC}"
  done

  box_end $w
}

# ── Goodbye Screen ────────────────────────────────────────────────────────────
draw_goodbye() {
  local w=60
  printf "\n"
  box_line $w
  box_row_empty $((w - 2))
  box_row_center $((w - 2)) "${DIM}Goodbye! Thanks for using PrivateTunes.${NC}"
  box_row_center $((w - 2)) "${DIM}github.com/Paidguy/PrivateTunes${NC}"
  box_row_empty $((w - 2))
  box_end $w
  printf "\n"
}
