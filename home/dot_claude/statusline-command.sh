#!/usr/bin/env bash
# Claude Code status line — ~/.claude/statusline-command.sh
#
# Design: one line, dense, instrument-grade. Renders on every turn, so the
# hot path is exactly TWO subprocesses — one `jq` for the whole payload,
# one `git` for the whole repo state. (The previous version spawned ten
# `jq` calls plus a `git symbolic-ref`.)
#
# Severity is never carried by color alone — every colored figure keeps its
# text label and units, so it still reads correctly through a no-color pipe.
#
# Segments, left to right:
#   dir  ⎇branch*dirty↑ahead↓behind  model·effort·flags  ctx%  5h/7d limits  $cost wall ±lines
#
# Payload schema confirmed against Claude Code 2.1.220. Fields NOT present
# and therefore not read: .worktree.name, .agent.name, .vim.mode — the old
# script read all three and they were always empty.

input=$(cat)

# ── single-pass parse: one jq, order matters ──────────────────────────────
# Delimiter is US (\x1f), NOT tab. Tab belongs to IFS' whitespace class, so
# `read` collapses runs of them and drops leading ones — any empty field
# would silently shift every later value one slot left. US is non-whitespace,
# so empty fields are preserved positionally. Values are flattened first so a
# stray newline cannot truncate the read.
IFS=$'\037' read -r cwd model_name effort \
    style ctx_used cost dur_ms lines_add lines_del \
    fh_pct fh_reset sd_pct sd_reset fast thinking big_ctx <<EOF
$(printf '%s' "$input" | jq -r '[
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // ""),
  (.effort.level // ""),
  (.output_style.name // ""),
  (.context_window.used_percentage // ""),
  (.cost.total_cost_usd // ""),
  (.cost.total_duration_ms // ""),
  (.cost.total_lines_added // ""),
  (.cost.total_lines_removed // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.rate_limits.seven_day.resets_at // ""),
  (.fast_mode // false),
  (.thinking.enabled // false),
  (.exceeds_200k_tokens // false)
] | map(tostring | gsub("[\n\r\t]"; " ")) | join("")')
EOF

# ── colors: real ESC bytes, so the final emit is printf '%s' (never %b).
# Branch names and paths are untrusted strings; %b would interpret any
# backslash sequence inside them.
R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
CY=$'\033[36m'; GN=$'\033[32m'; YL=$'\033[33m'; BL=$'\033[34m'
MG=$'\033[35m'; RD=$'\033[31m'
SEP="${D}│${R}"

# ── helpers ───────────────────────────────────────────────────────────────
# 26180478 -> 7h16m ; 95000 -> 1m35s
fmt_dur() {
    local ms=${1%%.*} s
    [ -z "$ms" ] && return
    s=$((ms / 1000))
    if   [ "$s" -ge 3600 ]; then printf '%dh%02dm' $((s / 3600)) $(((s % 3600) / 60))
    elif [ "$s" -ge 60 ];   then printf '%dm%02ds' $((s / 60)) $((s % 60))
    else printf '%ds' "$s"; fi
}

# unix-ts -> "2h14m" until reset (empty if already past)
fmt_until() {
    local target=${1%%.*} now delta
    [ -z "$target" ] && return
    now=$(date +%s); delta=$((target - now))
    [ "$delta" -le 0 ] && return
    if   [ "$delta" -ge 86400 ]; then printf '%dd%dh' $((delta / 86400)) $(((delta % 86400) / 3600))
    elif [ "$delta" -ge 3600 ];  then printf '%dh%02dm' $((delta / 3600)) $(((delta % 3600) / 60))
    else printf '%dm' $((delta / 60)); fi
}

# green <50, yellow <80, red >=80
pct_color() {
    local v=${1%%.*}
    [ -z "$v" ] && { printf '%s' "$GN"; return; }
    if   [ "$v" -ge 80 ]; then printf '%s' "$RD"
    elif [ "$v" -ge 50 ]; then printf '%s' "$YL"
    else printf '%s' "$GN"; fi
}

# ~/projects/cerebral-work/reverie -> ~/p/c-w/reverie
# The leaf stays whole (it is the part you actually read); interior
# components collapse to initials. Only engages past 3 components.
compact_path() {
    local p=$1
    # shellcheck disable=SC2088  # literal ~ for display, not expansion
    case "$p" in
        "$HOME") printf '~'; return ;;
        "$HOME"/*) p="~/${p#"$HOME"/}" ;;
    esac
    local IFS=/
    # shellcheck disable=SC2206  # deliberate split on IFS=/ set above
    local -a c=($p)
    local n=${#c[@]}
    if [ "$n" -le 3 ]; then printf '%s' "$p"; return; fi
    # Past 5 components, initial-abbreviating every interior segment produces
    # unreadable sludge (/p/t/c-5/-U-c/5-0-4…). Elide the middle instead and
    # keep the two components that carry meaning.
    if [ "$n" -gt 5 ]; then
        printf '%s/…/%s/%s' "${c[0]}" "${c[n-2]}" "${c[n-1]}"
        return
    fi
    local out=${c[0]} i seg
    for ((i = 1; i < n - 1; i++)); do
        seg=${c[i]}
        if [[ $seg == *-* ]]; then
            local IFS=-
            # shellcheck disable=SC2206  # deliberate split on IFS=- set above
            local -a w=($seg)
            # cerebral-work -> c-w, but only for genuinely word-like names;
            # 5-0-4-b-9 style noise just takes its first character.
            if [ ${#w[@]} -le 3 ]; then
                local j abbr=""
                for ((j = 0; j < ${#w[@]}; j++)); do abbr+="${w[j]:0:1}-"; done
                seg=${abbr%-}
            else
                seg=${seg:0:1}
            fi
        else
            seg=${seg:0:1}
        fi
        out+="/$seg"
    done
    printf '%s/%s' "$out" "${c[n-1]}"
}

# ── git: ONE call yields branch, upstream delta, and dirty count ──────────
git_seg=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    if gs=$(git --no-optional-locks -C "$cwd" status --porcelain=v2 --branch 2>/dev/null); then
        branch=$(printf '%s\n' "$gs" | awk '/^# branch.head /{print $3; exit}')
        ab=$(printf '%s\n' "$gs" | awk '/^# branch.ab /{print $3" "$4; exit}')
        # porcelain=v2: 1/2 = tracked change, u = unmerged, ? = untracked.
        # Tracked and untracked are counted separately — conflating them
        # makes a clean tree with scratch files look dirty.
        tracked=$(printf '%s\n' "$gs" | grep -c '^[12]')
        conflict=$(printf '%s\n' "$gs" | grep -c '^u')
        untracked=$(printf '%s\n' "$gs" | grep -c '^?')
        if [ "$branch" = "(detached)" ]; then
            branch="det@$(git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)"
        fi
        # long branch names are the single biggest width hog
        [ ${#branch} -gt 28 ] && branch="${branch:0:27}…"
        git_seg="${GN}⎇ ${branch}${R}"
        [ "${tracked:-0}" -gt 0 ] && git_seg+="${YL}*${tracked}${R}"
        [ "${untracked:-0}" -gt 0 ] && git_seg+="${D}?${untracked}${R}"
        [ "${conflict:-0}" -gt 0 ] && git_seg+="${RD}!${conflict}${R}"
        if [ -n "$ab" ]; then
            # shellcheck disable=SC2086
            set -- $ab
            [ "${1#+}" != "0" ] && git_seg+="${CY}↑${1#+}${R}"
            [ "${2#-}" != "0" ] && git_seg+="${MG}↓${2#-}${R}"
        fi
    fi
fi

# ── assemble ──────────────────────────────────────────────────────────────
parts=()

parts+=("${B}${CY}$(compact_path "${cwd:-$PWD}")${R}")
[ -n "$git_seg" ] && parts+=("$git_seg")

# model · effort · flags. Trim vendor prose: "Opus 5 (1M context)" -> "Opus 5".
if [ -n "$model_name" ]; then
    m=${model_name%% (*}
    [ "$big_ctx" = "true" ] && m+="·1M"
    [ -n "$effort" ] && m+="·${effort:0:3}"
    [ "$thinking" = "true" ] && m+="·◇"
    [ "$fast" = "true" ] && m+="·⚡"
    parts+=("${BL}${m}${R}")
fi
# a non-default output style is a mode you want to SEE, not rediscover
[ -n "$style" ] && [ "$style" != "default" ] && parts+=("${MG}${style}${R}")

# context
[ -n "$ctx_used" ] && parts+=("$(pct_color "$ctx_used")ctx ${ctx_used%%.*}%${R}")

# rate limits, with the reset countdown the old line discarded
rl=""
[ -n "$fh_pct" ] && rl="$(pct_color "$fh_pct")5h ${fh_pct%%.*}%${R}"
if [ -n "$sd_pct" ]; then
    [ -n "$rl" ] && rl+="${D}/${R}"
    rl+="$(pct_color "$sd_pct")7d ${sd_pct%%.*}%${R}"
fi
# whichever limit resets soonest is the one that will bite first
soon=""
[ -n "$fh_reset" ] && soon=$(fmt_until "$fh_reset")
[ -z "$soon" ] && [ -n "$sd_reset" ] && soon=$(fmt_until "$sd_reset")
[ -n "$soon" ] && rl+=" ${D}⟳${soon}${R}"
[ -n "$rl" ] && parts+=("$rl")

# cost · wall clock · churn
tail_seg=""
[ -n "$cost" ] && tail_seg="\$$(printf '%.2f' "$cost")"
if [ -n "$dur_ms" ]; then
    [ -n "$tail_seg" ] && tail_seg+=" "
    tail_seg+="$(fmt_dur "$dur_ms")"
fi
if [ -n "$lines_add" ] && { [ "$lines_add" != "0" ] || [ "${lines_del:-0}" != "0" ]; }; then
    [ -n "$tail_seg" ] && tail_seg+=" "
    tail_seg+="+${lines_add}/-${lines_del:-0}"
fi
[ -n "$tail_seg" ] && parts+=("${D}${tail_seg}${R}")

# ── emit ──────────────────────────────────────────────────────────────────
out=""
for p in "${parts[@]}"; do
    [ -z "$p" ] && continue
    if [ -z "$out" ]; then out="$p"; else out="$out $SEP $p"; fi
done
printf '%s\n' "$out"
