# WSL2 Clock-Step Stutter — Remediation Spec

**Status:** diagnosed, fix not yet applied · **Date:** 2026-06-02 · **Host:** Ceres
(WSL2, kernel `6.6.87.2-microsoft-standard-WSL2`) · **Owner:** Christian Todie

---

## 1. Problem (confirmed, not theorized)

Perceived terminal symptom: **"lag / freeze / stutter — input sluggish, periodically
hangs then catches up."**

Measured reality: **the VM never freezes.** A watchdog (`~/.local/bin/freeze-monitor`)
ran 50 min and logged **~95 `CLOCK-JUMP` events, ZERO `STALL` events**:

| Signal | Observation | Meaning |
|--------|-------------|---------|
| monotonic gap/tick | always **1.00s** | CPU/scheduler never stalls → NOT hooks, CPU, memory, or the mesh |
| wall-clock skew | discrete **+1.5–1.6s step every ~31s** | `CLOCK_REALTIME` is yanked forward on a fixed cadence |
| `clocksource` | `tsc` | correct; not a clocksource-selection bug |
| `timedatectl` | `NTP synchronized: yes` | clock stays *correct on average* — it's the *stepping* that hurts |
| CPU steal (`vmstat st`) | `0` | host is **not** starving the VM |
| uptime | **1 week 4h** | drift accumulates with uptime |

**Root cause:** the guest TSC runs slightly slow; WSL2 host time-sync periodically
**hard-steps `CLOCK_REALTIME` forward ~1.6s every ~31s** to re-match the host wall
clock. Any code that times off the wall clock (terminal key-repeat, render loops,
`select()`/poll timeouts) sees time lurch forward → *feels* like a freeze-then-catch-up.
It is a **clock-discipline defect, not a performance problem.**

Live re-confirmation: a 35s probe caught exactly one **+1.63s** step at t=21s
(net skew +1.633s over the window).

---

## 2. Diagnostic tool (reusable)

`~/.local/bin/freeze-monitor [logpath]` — Python watchdog. Targets a 1s tick and
compares monotonic vs wall each tick:

- **`STALL`** (monotonic gap ≥2s) → a *real* VM/scheduler freeze; logs load, MemAvailable,
  run-queue, D-state procs, top-CPU proc.
- **`CLOCK-JUMP`** (|wall−monotonic| ≥0.75s) → clock drift/step (this bug).
- **`ok …`** heartbeat every ~60 clean ticks.

Launch detached (survives the Claude session):
```bash
setsid ~/.local/bin/freeze-monitor /tmp/freeze-monitor.log >/dev/null 2>&1 < /dev/null &
```
⚠️ Do **not** prefix with `pkill -f freeze-monitor` — it self-matches the launching
shell and kills the whole command (exit 144). If an old instance exists, kill it by
explicit PID.

**Not yet chezmoi-managed.** Follow-up: `chezmoi add ~/.local/bin/freeze-monitor`
(→ `home/dot_local/bin/executable_freeze-monitor`) so it's reproducible. See §6.

---

## 3. Remediation options

### Option A — `wsl --shutdown` reset  ★ primary / most effective
Resets the WSL2 utility VM and re-calibrates the TSC against the host. Cures
accumulated-drift stepping outright.

**Steps (operator, in Windows PowerShell / Terminal — NOT inside WSL):**
1. Land a clean state first (see §4 handoff). Commit/park anything in flight.
2. `wsl --shutdown`
3. Reopen the WSL terminal (Windows Terminal / Warp / etc.).
4. Verify (§5).

**Blast radius:** kills **all** WSL processes — every Claude session, tmux, the
reverie mesh. Survives automatically:
- `reveried` — restarts via `systemctl --user` (lingering user unit).
- Engram DB (`~/.engram/engram.db`) — on disk, untouched. **No memory loss.**
- chezmoi-managed binaries/config — on disk.
Dies and must be relaunched: interactive Claude sessions, ad-hoc tmux panes, the
detached `freeze-monitor` (relaunch per §2).

**Reversible:** yes — it's a restart. Cost ≈ re-opening sessions.

### Option B — `wsl --update` then `wsl --shutdown`  (if A doesn't hold)
Same as A but first pull the latest WSL kernel/runtime (Microsoft has shipped TSC/
clock fixes). Use if the stepping **recurs** soon after a plain reset, which would
implicate a stale WSL build rather than just accumulated drift.
```powershell
wsl --update
wsl --shutdown
```

### Option C — In-guest chrony palliative  (non-disruptive stopgap)
Smooths the correction into a continuous **slew** instead of a visible **step**, so
the terminal never lurches — *without* a restart or any Windows action. Does **not**
fix the root TSC drift, and effectiveness is **uncertain** because WSL's built-in
host time-sync may keep stepping regardless (see caveat). Treat as "try + verify +
revert if no improvement."

**Apply (needs sudo):**
```bash
sudo apt-get install -y chrony
sudo systemctl disable --now systemd-timesyncd      # avoid two disciplinarians
sudo install -m 0644 /dev/stdin /etc/chrony/chrony.conf <<'CONF'
pool ntp.ubuntu.com iburst
driftfile /var/lib/chrony/chrony.drift
# Slew (don't step) once initial sync is reached, so the wall clock never lurches:
makestep 1.0 3
# Generous slew headroom to absorb the slow guest TSC smoothly (~5% ≈ 50000 ppm):
maxslewrate 83333
rtcsync
logdir /var/log/chrony
CONF
sudo systemctl enable --now chrony
```
**Verify:** rerun `freeze-monitor` for ~10 min → expect `CLOCK-JUMP` lines to vanish
or shrink well under the lurch threshold; `chronyc tracking` shows small, smooth
corrections.

**Caveat / known risk:** WSL2 performs its own host→guest time sync that this guest
config cannot disable cleanly. If `freeze-monitor` still logs ~+1.6s/31s steps after
chrony is active, WSL host-sync is overriding chrony — chrony cannot win, and Option
A is required.

**Revert:**
```bash
sudo systemctl disable --now chrony && sudo apt-get remove -y chrony
sudo systemctl enable --now systemd-timesyncd
```

### Option D — Standing watchdog  (optional, orthogonal)
Make `freeze-monitor` a `systemd --user` unit so drift is always observable and we
can tell next time whether it's clock-step (benign-ish) vs a true `STALL` (real
freeze worth escalating). Cheap; keep regardless of A/B/C.

---

## 4. Recommendation & sequence

1. **Now (non-disruptive):** Option C chrony as an immediate stopgap **iff** you need
   relief before you can restart. Verify with `freeze-monitor`; if WSL host-sync
   overrides it (caveat), skip to step 2.
2. **At next natural break:** Option A `wsl --shutdown`. This is the real fix; the
   reset costs little once sessions are wrapped.
3. **If it recurs within hours of reset:** Option B (`wsl --update` first).
4. **Keep:** Option D watchdog + add `freeze-monitor` to chezmoi (§6).

Decision driver: do you need relief *right now without restarting* (→ C first) or can
you take a 1-minute restart at the next break (→ A directly, skip C)?

---

## 5. Verification (common to all options)
```bash
# Re-arm the monitor, let it run ~10 min, then inspect:
setsid ~/.local/bin/freeze-monitor /tmp/freeze-monitor.log >/dev/null 2>&1 < /dev/null &
grep -cE 'CLOCK-JUMP' /tmp/freeze-monitor.log     # want: ~0 (was ~3/min)
grep -cE 'STALL'      /tmp/freeze-monitor.log     # want: 0 (already 0)
timedatectl | grep -i synchronized                # want: yes
```
Success = `CLOCK-JUMP` rate drops to ~0 and the terminal stops lurching.

---

## 6. Follow-up tasks (parked)
- [ ] `chezmoi add ~/.local/bin/freeze-monitor` → commit `feat(bin): add freeze-monitor WSL clock/stall watchdog` (signed).
- [ ] Commit the already-applied `zedw` `-e/--existing` doc update (working-tree change, uncommitted).
- [ ] (Optional) Option D systemd unit for the watchdog.
- [ ] Decide A vs B vs C per §4 and execute.

## 7. Open decisions for the operator
- **Relief-now vs restart-at-break** → picks C-first vs A-direct (§4).
- **Update WSL as part of the reset?** → A vs B (do it if drift recurs fast).
- **Keep the watchdog running as a unit?** → Option D yes/no.
