#!/usr/bin/env python3
"""Build a reveried-gate candidate from a subagent transcript (TOD-405).

Reads a Claude Code transcript JSONL file, extracts the last assistant
message text block, shapes it as `AddObservationParams` (the engram wire
format that `reveried gate` deserializes via serde), prints JSON on
stdout.

Prints empty string + exit 0 if:
  - transcript path doesn't exist
  - no usable assistant message found
  - assistant text is shorter than MIN_CONTENT_CHARS

IMPORTANT: field name is `type` (not `type_`) because
`AddObservationParams` uses `#[serde(rename = "type")]`. Emitting `type_`
fails to deserialize — this was caught during the TOD-405 rescue
(original design doc §3 had the wrong field name).

Valid `AddObservationParams` fields (anything else is silently dropped
by serde, which is fine but noise):
    session_id, type, title, content, tool_name, project, scope, topic_key
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

MIN_CONTENT_CHARS = 50
MAX_CONTENT_CHARS = 8000


def extract_last_assistant_text(transcript_path: Path) -> tuple[str, str]:
    """Return (title, content) from the last assistant message with a text block.

    Transcript is JSONL. Walk in reverse. Handle two common shapes:
        {"role": "assistant", "content": [{"type": "text", "text": "..."}, ...]}
        {"type": "assistant", "message": {"role": "assistant", "content": [...]}}
    """
    if not transcript_path.exists():
        return "", ""
    try:
        lines = transcript_path.read_text(errors="replace").splitlines()
    except OSError:
        return "", ""
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        role = obj.get("role")
        content = obj.get("content")
        if role is None and isinstance(obj.get("message"), dict):
            msg = obj["message"]
            role = msg.get("role")
            content = msg.get("content")
        if role != "assistant" or not isinstance(content, list):
            continue
        text_parts = [
            b.get("text", "")
            for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        ]
        text = "\n".join(p for p in text_parts if p).strip()
        if len(text) < MIN_CONTENT_CHARS:
            continue
        # Title = first non-empty line, trimmed to 80 chars.
        first_line = next((ln.strip() for ln in text.splitlines() if ln.strip()), "")
        title = first_line[:80] or "subagent turn"
        if len(text) > MAX_CONTENT_CHARS:
            text = text[: MAX_CONTENT_CHARS - 20] + "... [truncated]"
        return title, text
    return "", ""


def infer_project_from_cwd() -> str | None:
    """Best-effort project inference from CWD (`~/projects/<name>/...`)."""
    try:
        cwd = os.getcwd()
    except OSError:
        return None
    marker = "/projects/"
    idx = cwd.find(marker)
    if idx == -1:
        return None
    tail = cwd[idx + len(marker) :]
    return tail.split("/", 1)[0] if tail else None


def main() -> int:
    ap = argparse.ArgumentParser(description="Build a reveried-gate candidate")
    ap.add_argument("--session", required=True, help="Session ID from hook payload")
    ap.add_argument("--transcript", required=True, help="Path to transcript JSONL")
    args = ap.parse_args()

    title, content = extract_last_assistant_text(Path(args.transcript))
    if not content:
        print("", end="")
        return 0

    project = infer_project_from_cwd()
    candidate = {
        "session_id": args.session,
        "type": "auto-capture",
        "title": title,
        "content": content,
        "tool_name": "subagent-stop",
        "project": project,
        "scope": "project" if project else "personal",
    }
    # topic_key is omitted (null in JSON) — the dream cycle assigns later.
    print(json.dumps(candidate, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
