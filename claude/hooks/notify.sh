#!/usr/bin/env bash
# notify.sh — Send notification when Claude needs attention
# Uses Windows toast via PowerShell (WSL2), falls back to notify-send (native Linux)
set -euo pipefail

MSG=$(cat)
[ -z "$MSG" ] && MSG="Claude Code needs your attention"

# Escape single quotes for PowerShell
ESCAPED=$(echo "$MSG" | sed "s/'/\\\\'/g" | head -c 200)

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
