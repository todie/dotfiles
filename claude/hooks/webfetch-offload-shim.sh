#!/usr/bin/env bash
# webfetch-offload-shim — PreToolUse hook on the WebFetch tool that fetches
# the URL locally, strips HTML via w3m, summarizes via `llm --reason`
# (gemma4:e4b), and DENIES the WebFetch with the local summary so the
# actual tool call never consumes Claude API tokens on content processing.
#
# Skips + falls through to real WebFetch when:
#   - the URL ends in .md (already markdown; defuddle skill says don't touch)
#   - the URL is on a known auth-required host (github.com/api, internal tools)
#   - the WebFetch prompt contains "NO_OFFLOAD" (explicit opt-out)
#   - curl, w3m, or llm are missing
#   - anything fails — we fail-OPEN so the user always gets a result
#
# Budget: 25s total (5s curl, 20s llm --reason including cold-start)
# Log: /tmp/webfetch-offload-shim.log (one JSONL entry per invocation)

set -uo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "webfetch-offload"
log_init /tmp/webfetch-offload-shim.log

PAYLOAD=$(safe_read_stdin)
[ "$PAYLOAD" = '{}' ] && hook_allow

URL=$(json_field "$PAYLOAD" '.tool_input.url')
PROMPT=$(json_field "$PAYLOAD" '.tool_input.prompt')

# Guard: need both fields.
[ -z "$URL" ] && hook_allow
[ -z "$PROMPT" ] && hook_allow

# Opt-out flag in the prompt forces real WebFetch.
case "$PROMPT" in *NO_OFFLOAD*) log "skip: NO_OFFLOAD flag"; hook_allow ;; esac

# Skip .md URLs — they're already markdown, let real WebFetch handle.
case "$URL" in *.md|*.md\?*) log "skip: .md url url=$URL"; hook_allow ;; esac

# Skip known auth-required hosts. Add to this list as we find more.
case "$URL" in
  *github.com/api/*|*api.github.com/*|*api.linear.app/*|\
  *api.anthropic.com/*|*claude.ai/*|*vercel.com/api/*|\
  *docs.google.com/*|*drive.google.com/*)
    log "skip: auth-required host url=$URL"
    hook_allow ;;
esac

# Tool dependencies. Any missing → fall through.
require_cmd curl || { log "skip: no curl"; hook_allow; }
require_cmd w3m  || { log "skip: no w3m";  hook_allow; }
require_cmd llm  || { log "skip: no llm";  hook_allow; }

# Fetch the URL (5s timeout, follow redirects, strip content-encoding).
TMP=$(mktemp /tmp/webfetch-offload.XXXXXX.html)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -sSL --max-time 5 -o "$TMP" -w '%{http_code}' \
  -A 'Mozilla/5.0 (compatible; claude-webfetch-offload)' \
  "$URL" 2>/dev/null || echo "000")

case "$HTTP_CODE" in
  2??) : ;;
  *) log "skip: http=$HTTP_CODE url=$URL"; hook_allow ;;
esac

# Bail if the payload is suspiciously empty or massive.
BYTES=$(stat -c%s "$TMP" 2>/dev/null || echo 0)
if [ "$BYTES" -lt 200 ] || [ "$BYTES" -gt 5000000 ]; then
  log "skip: size=$BYTES url=$URL"
  hook_allow
fi

# Strip HTML → plain text via w3m. Cap at 8 KiB of text going into the LLM
# (gemma4:e4b has plenty of context, but longer prompts push latency up).
TEXT=$(w3m -dump -cols 100 -T text/html "$TMP" 2>/dev/null | head -c 8192)
if [ -z "$TEXT" ]; then
  log "skip: empty dump url=$URL"
  hook_allow
fi

# Call llm --reason with the user's prompt + extracted text.
# System prompt forces concise, direct output — matches what the real
# WebFetch returns (summarized content, not full HTML).
LLM_SYS="You extract information from web page content. Answer the user's \
question using only the provided page content. Be concise — 2-6 sentences \
unless the user explicitly asks for a list or long form. If the content \
does not answer the question, say so directly."

LLM_OUT=$(timeout 20 llm --reason --max 600 --temp 0.0 --sys "$LLM_SYS" \
  "User question: $PROMPT"$'\n\n'"Page URL: $URL"$'\n\n'"Page content:"$'\n'"$TEXT" \
  2>/dev/null)
LLM_RC=$?

if [ "$LLM_RC" -ne 0 ] || [ -z "$LLM_OUT" ]; then
  log "skip: llm_rc=$LLM_RC empty_out=$([ -z \"$LLM_OUT\" ] && echo yes || echo no) url=$URL"
  hook_allow
fi

# Strip the llm header (load_backend: ... lines when first-call).
CLEAN=$(echo "$LLM_OUT" | grep -v '^load_backend:')

log "OFFLOADED bytes=$BYTES text_len=${#TEXT} out_len=${#CLEAN} url=$URL"

hook_deny "[webfetch-offload] Fetched + summarized locally via gemma4:e4b (no Claude API tokens consumed on page content).

$CLEAN

(To bypass and hit real WebFetch: include \"NO_OFFLOAD\" in the prompt and retry.)"
