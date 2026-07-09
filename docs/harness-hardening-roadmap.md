# Harness Security Hardening — Execution Roadmap

> Milestone: **Harness security hardening (dotfiles)** · project Reverie · `6679c7c7-bd41-4b12-9300-6fb74e3b8b7c`
> Status (2026-06-08): **50 tickets** — 2 Done (CER-1061 PR #537 merged; CER-1076 shipped `09efa59`), 48 Backlog. All 50 carry a `phase-1/2/3` label.
> Spans two repos: **dotfiles** (the `~/.claude/hooks/*.sh` guards + `settings.json`) and **reverie** (the new `crates/reverie-guard*` Rust crates).

---

## TL;DR

- Your three lines (`fail-closed + jail arming` → `reverie-guard crate` → `sandbox + enforce`) map **1:1 onto the tickets' own Phase-1/2/3 tags**. This roadmap honours the ticket tags; no rebucketing.
- **The keystone is CER-1083** (guard decision/enforcement-split contract + shadow-mode schema). It is tagged Phase 1 but it is the structural root of the *whole* crate + shadow→enforce rollout — it blocks CER-1084, CER-1094, CER-1095, CER-1104. **Land it first.** It earns "Phase 0 / foundation" billing even though Linear tags it P1.
- **The critical path is the crate spine**, ~9 tickets with two L's and one L at the end:
  `1083 → 1084 → 1085 → 1086 → 1087 → 1088 → 1096 → 1097 → 1098`
  (contract → scaffold → tree-sitter parser → typed model → Cedar policy → secret-access migration → adversarial corpus → enforce cutover → provenance taint). Everything else parallelises around this.
- **Phase 3 cannot fully start after Phase 2** — the enforce-flip gate (CER-1103) has hard Phase-2 prerequisites (1093, 1094, 1095). The phases overlap at the seam by design.
- **Cross-milestone risk:** CER-1067/1068/1069 (Phase 2) and CER-1075 (Phase 3) are blocked by **CER-1057/1058/1059/1060, which live in `v0.10.0 — Audit-driven cleanup`, NOT this milestone.** The worker track is gated on work outside the milestone's control.

---

## How to read the phases

Each phase is a topological sort of its own tickets into **waves** — a wave is a set of tickets with no unmet in-phase dependency, runnable in parallel. `Sev` = severity from the ticket body. `Eff` = rough S/M/L. `Blocked by` lists only *hard* blockers (`blockedBy`), with `(P1)`/`(xM)` annotating which phase / which milestone the blocker lives in.

---

## Phase 1 — fail-closed + jail arming  *(16 tickets; shell-era, no Rust yet)*

**Goal:** make the *existing* shell guards correct and fail-**closed**, arm the jail + role-boundary for the *real* worker cwd, strip the config foot-guns, and lay the test-rollout foundation (corpus + runner + mode selector + the decision contract). This is the highest-ROI phase — it closes live CRITICAL holes with small shell edits.

### Wave 1.0 — Foundation keystone (do first, unblocks Phases 2–3)
| Ticket | Sev | Eff | What |
|---|---|---|---|
| **CER-1083** | CRIT | M | **Decision/enforcement-split contract + shadow-mode emit schema** (`reverie-guard-proto`). Typed `{decision, matched_rule_id, segment, provenance, reason, mode}` serde-tagged enum + a shell JSONL helper that round-trips to the Rust deserializer. Headless `ask→deny` pinned. *Blocks 1084, 1094, 1095, 1104.* |

### Wave 1.1 — Independent quick wins + roots (parallel)
| Ticket | Sev | Eff | What | Blocked by |
|---|---|---|---|---|
| **CER-1061** | CRIT | S | Export `REVERIE_MESH_ROLE` (+ `REVERIE_WORKTREE_JAIL`, session id) in the worker launcher — arms the dead `role-boundary-gate.sh`. ✅ **DONE — PR #537 merged.** *Unblocks 1066.* | — |
| **CER-1062** | CRIT | S | Arm `worktree-jail.sh` for the real `~/projects/reverie-wt-*` cwd + `REVERIE_WORKTREE_JAIL` key (jail currently no-ops for every worker). Mirror into `file-lock-gate.sh`. *Blocks 1063, 1064, 1065.* | — |
| **CER-1053** | CRIT | S | Flip `guard-dangerous-commands.sh` + `guard-secret-access.sh` from fail-**open** to fail-**closed** on jq-missing / unparseable / timeout. Delete the `[ -z "$COMMAND" ] && exit 0` antipattern. | — |
| **CER-1055** | HIGH | S | Remove `REVERIE_SKIP_CI_GATE=1` from global `settings.json` env (it permanently disables the pre-push gate). Per-command hatch stays. | — |
| **CER-1056** | HIGH | S | Remove over-broad `permissions.allow` wildcards (`eval *`, `/bin/bash *`, `. /*`, `cd …reverie && *`). **Interactive-only** until containment lands. | — |
| **CER-1054** | HIGH | M | Fence untrusted engram/skill output in `session-bootstrap-engram-drift.sh` as data, not a `<system-reminder>` (tag-injection escape). *Blocks 1071.* | — |
| **CER-1078** | HIGH | M | Bidirectional regression fixture for the two shell guards (`tests/guard-cases.sh`, MUST-BLOCK + MUST-ALLOW pairs, xfail for known-failing). *Blocks 1077, 1079.* | — |
| **CER-1080** | CRIT | M | Build the labeled corpora: `bypass.toml` / `false-positive.toml` / `fail-closed.toml` with finding `file:line` refs + xfail keys. *Blocks 1081.* | — |
| **CER-1082** | HIGH | S | Tri-state mode selector `off\|shadow\|enforce` per guard in `~/.claude/guard-modes.toml`; unknown/garbage → enforce (fail-closed). | — |

### Wave 1.2 — Depend on Wave 1.1
| Ticket | Sev | Eff | What | Blocked by |
|---|---|---|---|---|
| **CER-1063** | HIGH | S | Add `MultiEdit` to worktree-jail + role-boundary PreToolUse matchers. | 1062 |
| **CER-1064** | HIGH | S | Make worktree-jail + role-boundary fail **closed** on parse/jq error. *Blocks 1065 (P2).* | 1062 |
| **CER-1077** | HIGH | M | Close secret-leak indirection: `declare -p`/`typeset -p`, bare `set`, interpreter env-dumps. | 1078 |
| **CER-1079** | HIGH | S | `guard-secret-access`: catch split dir+filename (`cd ~/.ssh && cat id_rsa`) + `/proc/*/environ`. | 1078 |
| **CER-1081** | HIGH | M | Single corpus runner wired into `make ci-check` (NOT behind the untrustworthy pre-push gate). | 1080 |

### Already shipped — fix the Linear status
| Ticket | Sev | Eff | Note |
|---|---|---|---|
| **CER-1076** | HIGH | S | Per-segment force-push + recursive-rm matching. **Body says shipped (`09efa59` on dotfiles main) but Linear is Backlog.** → mark Done (decision below). |

---

## Phase 2 — reverie-guard crate  *(22 tickets; the Rust replacement + remaining shell containment + session-hook cleanup)*

**Goal:** stand up the `reverie-guard` crate in **shadow mode** (logs would-be decisions, shell regex stays live), build the tree-sitter→typed-model→Cedar-policy spine, migrate the guards onto it, finish the jail-escape + worker-policy containment, and clean the session-hook wiring. Shadow only — nothing enforces yet.

### Wave 2.0 — Crate critical path (the long pole — serialise these)
| Ticket | Sev | Eff | What | Blocked by |
|---|---|---|---|---|
| **CER-1084** | HIGH | M | Scaffold `crates/reverie-guard`; hook-contract CLI in **shadow** mode; install on PATH; missing-binary fails closed once enforce flips. | 1083 (P1) |
| **CER-1085** | CRIT | **L** | tree-sitter-bash per-segment parser: split on real operator nodes, typed argv, recursive unwrap of `bash -c`/`eval`/`source`/interpreter one-liners, flag normalisation. *Blocks 1086, 1092.* | 1084 |
| **CER-1086** | HIGH | M | Parse-don't-validate typed command model (serde-tagged enum); resolve relative paths vs cwd; illegal states unrepresentable. *Blocks 1087, 1089.* | 1085 |
| **CER-1087** | CRIT | **L** | Cedar default-deny / forbid-overrides-permit policy over the typed model. *Blocks 1088, 1093, 1096 (P3).* | 1086 |
| **CER-1088** | HIGH | M | Migrate `guard-secret-access.sh` onto parser + policy (zeroAccess dirs, env-dump variants). *Blocks 1096 (P3).* | 1087 |

### Wave 2.1 — Crate side-branches (parallel once their blocker lands)
| Ticket | Sev | Eff | What | Blocked by |
|---|---|---|---|---|
| **CER-1092** | HIGH | M | AST/per-segment parser test suite for the typed model. | 1085 |
| **CER-1089** | HIGH | M | `reverie-guard check --jail-root --cwd` path-scope subcommand; `worktree-jail.sh` becomes a thin wrapper. *Blocks 1099, 1101 (P3).* | 1086 |
| **CER-1093** | HIGH | M | Fail-closed error-injection test category against the redesigned guard. *Blocks 1103 (P3).* | 1087 |
| **CER-1095** | HIGH | M | Shadow-mode harness + baseline diff (the metric the enforce gate consumes). *Blocks 1103 (P3).* | 1083 (P1) |
| **CER-1094** | CRIT | **L** | Recursive-layer regression: prove guards actually fire **inside spawned workers** (the audit's dominant defect). *Blocks 1103, 1105, 1106 (P3).* | 1083 (P1) |

### Wave 2.2 — Containment (shell, after Phase-1 jail arming)
| Ticket | Sev | Eff | What | Blocked by |
|---|---|---|---|---|
| **CER-1091** | MED | M | Rust validator crate (`model/role/session-id/peer` + `record build`) for worker spawning. **Pulled forward from Phase 3** (no dependencies; kills the model-RCE / JSON-injection class directly). Runnable any time from Wave 2.0 onward. | — |
| **CER-1065** | CRIT | M | Close jail escapes: relative `cd`/`pushd`, `GIT_DIR`/`GIT_WORK_TREE`, effective-cwd tracking. Superseded later by 1089. | 1064, 1062 (P1) |
| **CER-1066** | CRIT | M | Compensate for `--dangerously-skip-permissions` with a generated per-role `--settings` allow/deny file scoped to the worktree. | 1061 (P1) |
| **CER-1090** | HIGH | M | Worker inherits main session's guard policy via a **signed policy handle** (`REVERIE_GUARD_POLICY` + sha); tamper → fail closed. *Blocks 1100 (P3).* | — |

### Wave 2.3 — Worker spawning  ⚠ blocked OUTSIDE this milestone
| Ticket | Sev | Eff | What | Blocked by |
|---|---|---|---|---|
| **CER-1067** | HIGH | M | Atomic FS lock steal (rename-then-verify), close TOD-647 TOCTOU. | **CER-1058 (×v0.10.0)** |
| **CER-1068** | HIGH | M | Heartbeat against a stable role-based session id; re-register on supervisor restart. | **CER-1060 (×v0.10.0)** |
| **CER-1069** | HIGH | S | Empty-worktree cleanup must refuse to destroy unmerged branches (`-d` not `-D`, merge-base check). | **CER-1059 (×v0.10.0)** |

### Wave 2.4 — Session-hook hygiene (independent track)
| Ticket | Sev | Eff | What | Blocked by |
|---|---|---|---|---|
| **CER-1070** | MED | S | `lib.sh`: add `json_field_strict` + write-path audit trail; stop masking jq errors. *Blocks 1071.* | — |
| **CER-1071** | HIGH | M | Fence + byte-cap raw engram smart-context in `session-bootstrap.sh` + `session-resume.sh`; shared `fence_untrusted`. | 1054 (P1), 1070 |
| **CER-1072** | HIGH | S | Wire `subagent-stop-capture.sh` + `build-gate-candidate.py` on `SubagentStop` (currently null). *Blocks 1074.* | — |
| **CER-1073** | MED | S | Retire unwired `worker-lifecycle.sh` (PID-keyed lock release matches nothing). *Blocks 1074.* | — |
| **CER-1074** | LOW | S | Strike false "wired" headers on `agent-auto-register` / `agent-preamble-check`; add a dormant/active/retired index. | 1073, 1072 |

---

## Phase 3 — sandbox + enforce  *(12 tickets; flip to enforcing + process-level confinement)*

**Goal:** define the measurable enforce-flip gate, flip shadow→enforce (shell becomes a thin shim over `reverie-guard`), retire the dead regex, add OS-level sandbox confinement (Landlock/seccomp/bwrap with WSL2 fallback), and prove the whole attack corpus is blocked end-to-end inside real workers.

### Wave 3.0 — Enforce gate prerequisites land first (the seam with Phase 2)
| Ticket | Sev | Eff | What | Blocked by |
|---|---|---|---|---|
| **CER-1103** | HIGH | M | Enforce-flip acceptance gate: 5 automatable criteria + FP budget threshold + single-flag rollback. *Blocks 1097.* | 1093, 1094, **1095** (all P2) |
| **CER-1096** | HIGH | M | Audit-derived adversarial regression corpus through the parse→typed→policy pipeline (verbatim ALLOW/BLOCK cases). *Blocks 1097.* | 1088, 1087 (P2) |
| **CER-1104** | MED | M | Decision-log observability: JSONL `matched_rule_id/segment/reason/mode`, secret redaction, log-failure-fails-closed. *Blocks 1105.* | 1083 (P1) |

### Wave 3.1 — Enforce cutover (critical-path tail — serialise)
| Ticket | Sev | Eff | What | Blocked by |
|---|---|---|---|---|
| **CER-1097** | HIGH | **L** | Shadow→enforce cutover: flip `REVERIE_GUARD_ENFORCE=1`, shell hooks become thin shims, delete dead regex, order after RTK rewrite, add MultiEdit/NotebookEdit matchers. *Blocks 1098.* | 1103, 1096 |
| **CER-1098** | MED | M | Per-argument provenance taint (CaMeL): untrusted-tainted destructive sink → deny where operator-fixed would ask. **Final ticket.** | 1097 |

### Wave 3.2 — Sandbox confinement (parallel pole)
| Ticket | Sev | Eff | What | Blocked by |
|---|---|---|---|---|
| **CER-1099** | HIGH | M | `reverie-guard sandbox-probe`: Landlock/seccomp/userns feature-detect + tier; graceful WSL2 fallback. *Blocks 1100, 1105.* | 1089 (P2) |
| **CER-1100** | HIGH | **L** | Confine workers with best tier (bwrap/Landlock+seccomp); FS+net allowlist, egress default-deny per role. | 1090 (P2), 1099 |
| **CER-1101** | MED | S | Audit/dry-run (`complain`) mode + decision logging for staged containment rollout. | 1089 (P2) |
| **CER-1105** | MED | M | Sandbox feature-detection tests: Landlock/seccomp with WSL2 fallback (never silently unconfined). | 1099, 1104, 1094 (P2) |

### Wave 3.3 — End-to-end adversarial proof
| Ticket | Sev | Eff | What | Blocked by |
|---|---|---|---|---|
| **CER-1106** | HIGH | **L** | Adversarial containment suite: spawn real workers vs an attack corpus, assert every control fires; wire into ci-check. | 1094 (P2) |
| **CER-1075** | MED | M | Adversarial harness for the worker-spawn fixes feeding the unified runner. ⚠ | **1067/1068/1069** (→ ×v0.10.0) |

---

## Critical path & sequencing summary

```
PHASE 1 keystone        1083 ───────────────────────────────────────────────┐
                                                                            │
crate spine (P2→P3)     1084 → 1085 → 1086 → 1087 → 1088 ──────► 1096 ──┐   │
                                       │                                │   │
enforce-gate inputs     1083 ─► 1095 ──┤                                ▼   │
                        1083 ─► 1094 ──┼──────────────► 1103 ──────► 1097 → 1098
                        1087 ─► 1093 ──┘                                ▲
sandbox pole            1086 ─► 1089 ─► 1099 ─► 1100 ; 1104 ─► 1105     │
```
**Longest chain:** `1083 → 1084 → 1085(L) → 1086 → 1087(L) → 1088 → 1096 → 1097(L) → 1098` — three L-effort tickets on one chain. This is the schedule driver; resourcing here moves the whole milestone.

## Cross-cutting risks / watch items
1. **Cross-milestone gate.** CER-1067/1068/1069/1075 depend on CER-1057–1060 in `v0.10.0`. If that milestone stalls, the entire worker-spawn track stalls — independent of any work here.
2. **Two repos, one milestone.** Phase 1 is mostly dotfiles (`~/.claude/hooks/*.sh`, `settings.json`); Phases 2–3 add `crates/reverie-guard*` in the reverie repo. The "(dotfiles)" milestone name undersells the reverie-side weight.
3. **RTK ordering invariant (CER-1097).** `reverie-guard` must run *after* the RTK rewrite hook so it sees the post-rewrite executed form; RTK files are sha256-locked (ordering is the only lever). Document and test this.
4. **`settings.json` is shared, claude-config–locked.** Every matcher change (1063, 1072, 1097) touches it — take the `claude-config` lock; serialise those edits.
5. **CER-1076 status drift** — shipped code filed as Backlog skews milestone progress and could trigger a duplicate attempt.

## Decisions (resolved 2026-06-08)
- **CER-1076 drift** → mark **Done** in Linear. ✓
- **Cross-milestone worker-spawn (1057–1060)** → **keep as external dependency**; track here, do not re-home. The worker-spawn track (1067/1068/1069/1075) waits on `v0.10.0`.
- **CER-1091** → **pulled forward to Phase 2 / Wave 2.2** (no deps; kills model-RCE / JSON-injection class early).
- **Linear sync** → **apply** phase labels (`phase-1/2/3`) + execution ordering to the milestone tickets, mirroring this roadmap. Roadmap remains the narrative source of truth; Linear carries the labels + sort.
