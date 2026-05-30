#!/usr/bin/env bash
# notify.sh — Send notification when Claude needs attention
# Uses Windows toast via PowerShell (WSL2), falls back to notify-send (native Linux)
set -euo pipefail

RAW=$(cat)
# The Notification event is a JSON envelope — surface its .message, not the
# raw {...} blob. Fall back to raw text (non-JSON callers) then a default.
MSG=$(printf '%s' "$RAW" | jq -r '.message // empty' 2>/dev/null)
[ -z "$MSG" ] && MSG="$RAW"
[ -z "$MSG" ] && MSG="Claude Code needs your attention"

# PowerShell single-quoted literals escape an embedded quote by DOUBLING it
# ('') — backslash is literal and does NOT escape. The old s/'/\'/g left every
# apostrophe able to terminate CreateTextNode('…') and run the remainder as
# PowerShell on the Windows host (RCE). Cap first, then double quotes, so the
# message is inert DATA inside the literal.
ESCAPED=$(printf '%s' "$MSG" | head -c 200 | sed "s/'/''/g")

if command -v powershell.exe &>/dev/null; then
  powershell.exe -NoProfile -Command \
    "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null; \
     \$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(0); \
     \$xml.GetElementsByTagName('text')[0].AppendChild(\$xml.CreateTextNode('$ESCAPED')) | Out-Null; \
     [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show(\
       [Windows.UI.Notifications.ToastNotification]::new(\$xml))" 2>/dev/null &
elif command -v notify-send &>/dev/null; then
  notify-send 'Claude Code' "$MSG" 2>/dev/null
fi

exit 0
