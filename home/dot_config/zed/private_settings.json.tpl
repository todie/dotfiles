// Zed settings
//
// For information on how to configure Zed, see the Zed
// documentation: https://zed.dev/docs/configuring-zed
//
// To see all of Zed's default settings without changing your
// custom settings, run `zed: open default settings` from the
// command palette (cmd-shift-p / ctrl-shift-p)
{
  "cli_default_open_behavior": "existing_window",
  "terminal": {
    "shell": {
      "program": "zsh"
    },
    "font_family": "JetBrainsMono Nerd Font",
    "font_size": 14
  },
  "session": {
    "trust_all_worktrees": true
  },
  "redact_private_values": true,
  "proxy": "",
  "agent": {
    "tool_permissions": {
      "tools": {
        "terminal": {
          "default": "confirm"
        }
      }
    },
    "default_model": {
      "effort": "high",
      "provider": "zed.dev",
      "model": "claude-sonnet-4-6",
      "enable_thinking": true
    },
    "favorite_models": [],
    "model_parameters": []
  },
  "context_servers": {
    "container-use-mcp": {
      "enabled": true,
      "remote": false,
      "settings": {}
    },
    "mcp-server-slack": {
      "enabled": false,
      "remote": false,
      "settings": {
        "slack_bot_token": "op://cloud/Slack Bot Token/credential",
        "slack_team_id": "op://cloud/Slack Bot Token/team_id",
        "slack_channel_ids": "op://cloud/Slack Bot Token/channel_ids"
      }
    },
    "github-activity-summarizer": {
      "enabled": true,
      "remote": false,
      "settings": {}
    },
    "mcp-server-github": {
      "enabled": true,
      "remote": false,
      "settings": {
        "github_personal_access_token": "op://cloud/xeyhu6cuy4m7aiizwypkxvl5bq/token"
      }
    }
  },
  "agent_servers": {
    "qwen-code": {
      "type": "registry"
    },
    "claude-acp": {
      "type": "registry"
    },
    "gemini": {
      "type": "registry"
    }
  },
  "ui_font_size": 16,
  "ui_font_family": "JetBrainsMono Nerd Font",
  "buffer_font_size": 15,
  "buffer_font_family": "JetBrainsMono Nerd Font",
  "theme": {
    "mode": "system",
    "light": "One Light",
    "dark": "Synthwave84",
  },
}
