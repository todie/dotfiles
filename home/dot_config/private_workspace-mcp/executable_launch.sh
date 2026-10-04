#!/usr/bin/env bash
# workspace-mcp launcher — Gmail, read-only, 3 accounts.
#
# The OAuth client is read from 1Password at launch (never on disk here),
# matching the ~/.claude/mcp/1password.json pattern. Per-account refresh
# tokens are written by the server to ./credentials/ as mode-600 JSON;
# revoke at https://myaccount.google.com/permissions.
set -euo pipefail

# OP_SERVICE_ACCOUNT_TOKEN lives in ~/.secrets (operator-managed).
[ -f "$HOME/.secrets" ] && { set -a; . "$HOME/.secrets"; set +a; }

GOOGLE_OAUTH_CLIENT_ID="$(op read 'op://workstation-keys/gmail-mcp-oauth/client_id')"
GOOGLE_OAUTH_CLIENT_SECRET="$(op read 'op://workstation-keys/gmail-mcp-oauth/credential')"
export GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET
export WORKSPACE_MCP_CREDENTIALS_DIR="$HOME/.config/workspace-mcp/credentials"

# --read-only: requests only read-only scopes AND disables write tools.
# --tools gmail: Gmail only; no Drive/Calendar/Docs surface.
exec uvx --from workspace-mcp workspace-mcp \
  --transport stdio \
  --tools gmail \
  --read-only
