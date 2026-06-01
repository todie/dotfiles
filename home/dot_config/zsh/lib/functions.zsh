# functions.zsh — utility functions available across all zsh sessions

# ── color helpers ────────────────────────────────────────────────────────────
# Hardcoded SGR escapes instead of 9 `tput` forks per shell start (perf). Only
# emit color when stdout is a TTY; otherwise leave the vars empty so piped/
# logged output stays clean. Codes are the standard ANSI set tput would return.
if [[ -t 1 ]]; then
  BOLD=$'\e[1m'      UNDERLINE=$'\e[4m'  NO_COLOR=$'\e[0m'
  GREY=$'\e[30m'     RED=$'\e[31m'       GREEN=$'\e[32m'
  YELLOW=$'\e[33m'   BLUE=$'\e[34m'      MAGENTA=$'\e[35m'
else
  BOLD='' UNDERLINE='' NO_COLOR='' GREY='' RED='' GREEN='' YELLOW='' BLUE='' MAGENTA=''
fi

pinfo()      { printf '%s\n' "${BOLD}${GREY}>${NO_COLOR} $*"; }
pwarn()      { printf '%s\n' "${YELLOW}! $*${NO_COLOR}"; }
perror()     { printf '%s\n' "${RED}x $*${NO_COLOR}" >&2; }
pcompleted() { printf '%s\n' "${GREEN}✓${NO_COLOR} $*"; }

pdebug() {
  (( ${DOTFILES_ZSH_DEBUG:-0} > 0 )) && printf '%s\n' "${BLUE}# $*${NO_COLOR}"
}

# ── capability detection ─────────────────────────────────────────────────────
has()      { command -v -- "$1" 1>/dev/null 2>&1; }
readable() { [[ -r "$1" ]]; }

detect_arch() { uname -m | tr '[:upper:]' '[:lower:]'; }
detect_os()   { uname -s | tr '[:upper:]' '[:lower:]'; }

# ── string helpers ───────────────────────────────────────────────────────────
# Strip leading whitespace from a nameref variable in place.
dedent() {
  local -n reference="$1"
  reference="$(printf '%s' "$reference" | sed 's/^[[:space:]]*//')"
}

# ── download / unpack ────────────────────────────────────────────────────────
download() {
  local url="$1" file="${2:-$(basename "$1")}"
  if has curl; then
    curl -fsSL -o "$file" "$url" && return 0
    local rc=$?
    perror "curl failed (exit $rc): ${BLUE}$url${NO_COLOR}"
    return $rc
  fi
  perror "curl not found. Install curl and try again."
  return 1
}

unpack() {
  local archive="$1" bin_dir="$2" sudo="${3-}"
  case "$archive" in
    *.tar.gz)
      mkdir -p "$bin_dir"
      local flags; flags=$(test -n "${VERBOSE-}" && echo "-xzvf" || echo "-xzf")
      ${sudo} tar "$flags" "$archive" -C "$bin_dir" --strip-components=1
      ;;
    *.zip)
      local flags; flags=$(test -z "${VERBOSE-}" && echo "-qq" || echo "")
      UNZIP="$flags" ${sudo} unzip "$archive" -d "$bin_dir"
      ;;
    *)
      perror "unpack: unknown archive type '$archive'."
      return 1
      ;;
  esac
}
