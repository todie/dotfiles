#!/bin/bash
# Hook: sync new engram observations to Obsidian vault at session end.
# Runs silently — only outputs on error.
engram-to-obsidian 2>/dev/null >/dev/null || true
