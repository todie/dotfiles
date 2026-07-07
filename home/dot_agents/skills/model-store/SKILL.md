---
name: model-store
description: Manage the local and remote (Cloudflare R2) model collection with the model-sync CLI — inventory local model dirs, push finished models to the r2:model-collection bucket, pull them back, verify remote copies, and safely prune local copies to reclaim disk. Use when the user says "back up the model", "push to R2", "how much space are models using", "pull <model> down", "free up disk", or after a heretic run produces a new decensored model. Args — subcommand (status|ls|push|pull|verify|prune-local) and its args, passed straight to model-sync.
---

# Model Store

One tool: `model-sync` (in `~/.local/bin`, on PATH). Bucket: `model-collection`
on Cloudflare R2, account `07ae57cca8fc1a438f9c9b875d1e2283`, rclone remote `r2`.

## Credentials

rclone.conf holds endpoint only. Keys come from `~/.config/rclone/r2.env`
(chmod 600) or `RCLONE_CONFIG_R2_ACCESS_KEY_ID` / `RCLONE_CONFIG_R2_SECRET_ACCESS_KEY`
env vars. If missing, ask the user to mint an **R2 API token (Object Read &
Write)** in the Cloudflare dashboard — the wrangler OAuth token cannot create
one. Capture the secret with the `reverie-secret-page` skill, never via chat.

## Layout

- Remote: `r2:model-collection/<model-name>/` — one prefix per model, full
  HF-format dir (config.json, *.safetensors, tokenizer, Modelfile if present).
- Local working copies: `~/models` (ollama-served), project output dirs.
- Local archive: `~/model-archive/<model-name>/`.

## Commands

```bash
model-sync status                 # inventory + disk + remote listing
model-sync push <dir> [name]      # upload + size-verify
model-sync pull <name> [dest]     # restore locally
model-sync prune-local <dir>      # delete local ONLY after remote verify
```

## Rules

- Never `rm` a local model dir directly — use `prune-local` so the remote copy
  is verified first.
- HF cache (`~/.cache/huggingface`) is NOT backed up — it is re-downloadable.
  Reclaim space there with `huggingface-cli delete-cache` instead.
- After every successful heretic run: `model-sync push <output-dir>`.
