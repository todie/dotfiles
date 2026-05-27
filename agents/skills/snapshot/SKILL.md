---
name: snapshot
description: Take a headless-chrome screenshot of a URL and save it to /tmp for visual verification. Use when you need to see the rendered result of a web page, preview deploy, or local dev server instead of inferring from HTML/JS source. Default to /snapshot over Grep-and-guess when the user pushes a visual change and asks you to verify it. Args — URL (required), viewport (WIDTHxHEIGHT, default 1400x900), scale (1 or 2, default 2), full-page (y/n, default n, when y uses a 5200px tall viewport to capture the whole page).
---

# Snapshot

Take a headless-chrome screenshot of a URL and save it to `/tmp/snapshots/` so it can be `Read` visually. This is the pure encapsulation of the snapshot-review loop that gets re-run dozens of times during any visual design pass.

## When to use

- User deployed a visual change and asks you to verify it
- You just pushed a PR preview and need to see the rendered result
- You're iterating on a design and need to compare before/after
- You need to check whether a visual bug actually reproduces in a browser

**Don't** use this for:
- Static HTML inspection (use `curl` + `Read` instead)
- Checking bundle contents (`grep` the JS bundle instead)
- URLs you don't need to *see* (don't screenshot just because you can)

## Requirements

- `google-chrome` or `chromium-browser` installed. On WSL2 / Ubuntu the binary is usually `/usr/bin/google-chrome`. Verify with `which google-chrome` if the command fails.
- `/tmp/snapshots/` is the output dir. Create it if it doesn't exist.

## Usage

```bash
mkdir -p /tmp/snapshots
OUT="/tmp/snapshots/$(date +%s)-$(echo "URL" | sed 's|[^a-zA-Z0-9]|_|g' | cut -c1-40).png"
google-chrome --headless --disable-gpu --no-sandbox \
  --window-size=WIDTH,HEIGHT \
  --force-device-scale-factor=SCALE \
  --screenshot="$OUT" \
  "URL" 2>&1 | grep -E 'bytes written|error' | head -3
```

Then `Read` the saved file to view the image visually.

## Defaults

| Flag | Default | Meaning |
|---|---|---|
| viewport | `1400x900` | Standard desktop width. Height is enough for a hero + first fold. |
| scale | `2` | 2× device scale factor for sharp text at small sizes (mimics Retina display). Use `1` for mobile or when the default PNG is too large. |
| full-page | `n` | When `y`, override height to `5200` (or higher) to capture the entire scroll of a long article without stitching. |

## Variants

**Full-page (long article):**
```bash
google-chrome --headless --disable-gpu --no-sandbox \
  --window-size=1400,5200 \
  --screenshot="/tmp/snapshots/$(date +%s)-full.png" \
  "URL"
```

**Mobile viewport:**
```bash
google-chrome --headless --disable-gpu --no-sandbox \
  --window-size=390,844 \
  --force-device-scale-factor=2 \
  --screenshot="/tmp/snapshots/$(date +%s)-mobile.png" \
  "URL"
```

**Before/after (two shots, same args):**
Take one shot, rename it `-before.png`, make the change, take another, save as `-after.png`. `Read` both in parallel.

## Cleanup

`/tmp` is volatile on most systems. Old snapshots age out on reboot. If you want to clear them yourself, `rm /tmp/snapshots/*.png` — but don't do this proactively; the user might want to compare against an older shot.

## Expected output

Chrome prints two kinds of noise to stderr that should be ignored:
- `ERROR:base/memory/shared_memory_switch.cc ... Failed global descriptor lookup` — harmless
- `ERROR:dbus/object_proxy.cc ... org.freedesktop.DBus.Error.ServiceUnknown` — harmless WSL2 quirk

The signal is the `N bytes written to file ...` line. If that's present, the PNG is valid.
