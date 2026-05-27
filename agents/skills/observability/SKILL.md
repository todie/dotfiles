---
name: observability
description: Add, audit, or upgrade observability (Prometheus metrics, structured tracing, /health endpoints, log shipping, dashboards, and cross-service mesh telemetry) on a Rust service or a multi-service mesh. Use when the user asks to instrument a crate, "make it observable", surface telemetry, wire metrics, ship logs, build or audit a dashboard, audit existing observability for cardinality/over-request/sampling bugs, or propose improvements across an entire project / fleet of services. Codifies the dashboard-manager playbook used on revenant + reverie. Args — optional `mode=audit|upgrade|mesh|dashboard`, `crate=<name>` or `path=<dir>` to target a specific crate; defaults to a full-workspace sweep that audits every service and proposes the next iteration for each.
---

# observability

Add real telemetry to a Rust service in small reviewable iterations. This skill exists because every "make it observable" task converges on the same checklist, and shipping it ad-hoc misses things (label cardinality blowups, over-request loops, 1-second histogram floors hiding p99s).

## When to use

- The user asks to instrument a crate, add metrics, ship logs, build a dashboard
- The user asks why a service is "burning API calls" or "feels blind in prod"
- A new HTTP/gRPC/MCP service was added without observability scaffolding
- A code review surfaces a missing counter, span, or `/health` endpoint
- The user asks for an observability audit on an existing service

Don't use for:
- Pure log-statement noise reduction (just edit the log line)
- Adding a single `tracing::info!` to debug something locally
- Frontend telemetry / browser RUM

## The playbook — apply in order, one per iteration

The point of doing this in order is that each layer needs the one below it to be useful. A dashboard with no metrics endpoint is a wishlist; metrics with no scrape config don't flow.

### 1. `/metrics` endpoint (Prometheus text format)
- Add `prometheus = "0.13"` (or `metrics = "0.23"` + `metrics-exporter-prometheus` if the user prefers the `metrics` crate facade) gated behind the existing HTTP-server feature flag, never as a hard dep.
- Create a `metrics` submodule next to the HTTP router. Use a `OnceLock<HttpMetrics>` global, not lazy_static.
- Register at minimum: `requests_total{route,method,status}`, `request_duration_seconds{route,method}` histogram, `in_flight` gauge, `build_info{version}` const-labeled gauge set to 1.
- **Bound label cardinality** — pull `route` from axum's `MatchedPath` (the route template), never the request URL. Status as a string is fine (it's bounded). User IDs / request IDs / paths are NOT bounded — never label on them.
- **Sub-10ms histogram buckets for hot paths.** The default Prometheus buckets start at 5ms and the `prometheus` crate's defaults start at 1s. Both are useless for sub-millisecond services. Use `[0.001, 0.002, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]` as the starting point and adjust to the workload's actual p50/p99.
- Exclude `/metrics` itself from the request counter so scrapes don't dominate volume.

### 2. Tracing — JSON mode toggle in `init_tracing`
- Honor `LOG_FORMAT=json` → ndjson on stderr, anything else → human fmt.
- Honor `LOG_SPANS=1` → `FmtSpan::CLOSE` events with elapsed time. Default off.
- JSON mode: enable `with_file(true).with_line_number(true).with_thread_ids(true).with_current_span(true)`.
- Both modes write to **stderr**, never stdout. Stdout is reserved for protocol traffic (MCP stdio, gRPC, structured CLI output).
- The `tracing-subscriber` `json` feature must be in the workspace Cargo.toml — check and add if missing.

### 3. `/health` endpoint
- Liveness: a static 200 with `{"status":"ok"}`. Don't make it depend on downstream health or it stops being a liveness probe.
- Readiness (separate `/ready` if the user wants K8s semantics): check the database is reachable and any background loops are alive (last-heartbeat timestamp gauge).
- Both endpoints must NOT be authenticated and must NOT be rate-limited.

### 4. Domain instrumentation
- Wrap the hot-path functions with `#[tracing::instrument(skip(..), fields(...))]` — skip large args, add small computed fields. Never log full request bodies in spans.
- For each external call (DB, HTTP, LLM API), add a counter `<service>_<verb>_total{kind,status}` and a duration histogram. **This is what catches over-request bugs** — see "audit checklist" below.
- Increment the counter on **call start** (or in a RAII guard), not just on success. Otherwise a runaway error loop is invisible.

### 5. Scrape config + log shipping
- Add a `prometheus.yml` job under `observability/` (or extend the existing one).
- For logs: Loki + promtail OR Vector. JSON-mode tracing slots into either with no transformation.
- Scrape interval: 15s default; 5s for fast-moving services.

### 6. Dashboard
- Static `dashboard/index.html` (vanilla JS, no build step) for a single-service view, OR Grafana JSON under `observability/grafana/dashboards/` for multi-service.
- Required panels: request rate (by route), p50/p95/p99 latency (by route), error rate, in-flight, plus per-domain panels for the counters added in step 4.
- For dream/pipeline services: per-phase duration heatmap.

### 7. Cross-service telemetry (multi-process / multi-session)
- If sessions/workers communicate via filesystem (e.g. `/tmp/<service>/sessions/*.json` like coord), build a small exporter task that scans that directory every N seconds and updates a `<service>_sessions{role,status}` gauge.
- Don't create a separate exporter binary unless the source service can't host it — just spawn a tokio task in the existing daemon.

## Audit checklist (use when the user says "is this observable" or "why is it burning API calls")

Read the suspect files and look for ALL of these:

1. **Over-request loops** — any `loop { call_external_api(); sleep(); }` where:
   - The duplicate/skip path doesn't update the next-call backoff (post_generator pattern from revenant)
   - Two dedup keys disagree so the same item gets re-processed every poll (scanner pattern from revenant)
   - There's no max-retry, no exponential backoff, no per-iteration budget
2. **Missing call counters** — every external API call site needs a `*_total` counter incremented on entry. Without this, runaway burn is invisible until the bill comes.
3. **Cardinality bombs** — label values that are unbounded: user IDs, request paths, URLs, free-text. Replace with route templates, hash buckets, or drop the label.
4. **1-second histogram floors** — `vec![1.0, 2.0, 5.0, ...]` on a service whose p50 is 50ms means every observation falls in the 1s bucket and you can't see anything.
5. **Stdout pollution** — `println!` or `tracing` writing to stdout in a service that also speaks a protocol on stdout (MCP stdio, gRPC) → corrupted protocol frames.
6. **Silent task panics** — `tokio::spawn` without supervision. If the task dies, no metric records it. Either supervise (exit and restart) or wrap the spawn in a panic counter.
7. **Scrape-self loop** — `/metrics` endpoint counted by its own request counter. Inflates volume and hides real traffic.

For each finding: cite the file and line, explain what it costs (API $, p99, blast radius), and provide a small fix.

## Work cadence

- One observation layer per iteration (metrics → tracing → /health → instrumentation → scrape → dashboard → cross-service).
- Run `cargo check -p <crate>` (and `cargo test -p <crate>` if tests touch the modified surface) before reporting.
- Report in 3-5 lines: what you added, what cargo confirmed, what's queued for next iteration.
- Never commit observability code that doesn't compile or that breaks existing tests.

## Pitfalls from real iterations

These are mistakes that have actually shipped on this codebase. Read before each iteration.

1. **`cargo check` is NOT a substitute for `cargo build --release` when verifying instrumentation lands in the running binary.** `cargo check` will happily green-light code whose new metric is feature-gated out of the release profile, or whose new symbol never makes it into `target/release/<bin>` because a different feature set is active. If the user is going to hot-swap the binary (`reveried-swap`, engram-serve cutover), run `cargo build --release -p <crate>` and grep the resulting binary for the new metric name (`strings target/release/<bin> | grep <metric>`) before declaring done. This bug bit a real iteration: a counter passed `cargo check`, was never in `target/release/`, and the dashboard panel stayed flat post-swap.
2. **RAII timer helper for store/query duration histograms.** When instrumenting a hot-path function with both a counter and a histogram, don't `let start = Instant::now(); ...; histogram.observe(start.elapsed())` at every return site — early returns and `?` propagation will skip it. Define a small `StoreQueryTimer` struct that holds the histogram handle and the start instant, observes in `Drop`, and bind it at the top of the function (`let _t = StoreQueryTimer::new(&METRICS.store_query_duration, "by_id");`). One line, all return paths covered, panics still record. This is the canonical pattern for any external-call duration histogram in this workspace.
3. **Hot-swap requires the `engram-serve` coord lock.** Any iteration that ends in swapping `~/.local/bin/engram` (the reveried binary) must hold `coord lock engram-serve` for the duration of the build + swap + smoke test, and release on success or rollback. Skipping the lock races other sessions that may be mid-request against the daemon and corrupts in-flight observations. The `reveried-swap` skill handles this — prefer it over hand-rolling the swap.
4. **Iter numbering vs. file numbering drift.** When this skill is driven by a cron loop, the "iter N" the cron reports and the "file N" on disk (e.g. `iter-007-metrics.md`) drift the moment a tick is skipped or a file is renamed. Always record both in the report footer (`iter 12 = file iter-009-store-query-histogram.md`) so the next tick can reconcile without re-reading the whole directory.
5. **Dashboard CORS / same-origin trap.** A standalone dashboard HTML file that fetches `/metrics` (or any relative URL) MUST be served from the same origin as the metrics endpoint, OR the metrics endpoint must set `Access-Control-Allow-Origin: *`. Opening `dashboard/index.html` via `file://` or hosting it on a different port silently fails — the browser blocks the fetch with a CORS error and the panels stay empty, which looks identical to "metrics endpoint is broken." The cleanest fix on this codebase is to embed the dashboard HTML into the serving binary via `include_str!("../dashboard/index.html")` and serve it from a `/dashboard` route on the same axum router that owns `/metrics`. Same origin, zero CORS config, no static file server to deploy. This bug shipped as iter 9 ("dashboard isn't showing fix it") — the metrics endpoint was fine the entire time; the dashboard was on the wrong origin.
6. **Docker Desktop on WSL2 single-file bind mounts are fragile.** When the host file backing a `-v /host/path/file:/container/path/file` mount is rm'd and rewritten (even with the same content), Docker Desktop's bind-mount snapshot dies and the container can't restart — `docker restart` fails with `mount ...: no such file or directory` because the WSL2 bind-mount cache holds a stale snapshot path. Recovery: `docker rm` the dead container and `docker run` a fresh one with a **directory** bind mount instead (`-v /host/dir:/container/dir`), then use `--web.enable-lifecycle` (for prometheus) or equivalent so future config reloads happen via HTTP/SIGHUP without touching docker. This bug bit a real iteration when prometheus.yml was rewritten in place during the iter-10 telemetry attach work — recovery required extracting the original spawn config from `docker inspect` and recreating the container with the directory mount + lifecycle flag.
7. **OTLP `with_batch_exporter(_, runtime::Tokio)` panics with "there is no reactor running" when `init_tracing` is called from plain `fn main`.** The batch exporter spawns its background flush task onto the current tokio runtime *at construction time*, not at first export — so if your binary builds the tracing subscriber in `main()` before any per-command `Runtime::new()` / `#[tokio::main]` scope, the constructor blows up before the first span ever fires. This bit iter 14b: tracing wired correctly, OTLP endpoint reachable, daemon crashed on boot. Two valid fixes: (a) move `init_tracing` *inside* the tokio runtime (call it as the first thing in `#[tokio::main] async fn main` or inside `rt.block_on(async { init_tracing(); ... })`), or (b) for low-volume daemons (<100 spans/sec), use `with_simple_exporter` instead — it exports synchronously per-span on the calling thread, no background task, no runtime requirement, and the throughput cost is irrelevant at this scale. The opentelemetry-rust docs default to `with_batch_exporter` and never mention this constraint; treat `with_simple_exporter` as the correct default for any Rust daemon whose tracing init runs outside an async context. Verify post-fix by booting the binary with `RUST_LOG=opentelemetry=debug` and confirming you see `"exporter started"` without a panic, then curl one request and confirm the span lands in Tempo/Jaeger within 5s.
8. **Dashboard panels that depend on metrics from a different exporter must be reachability-verified BEFORE shipping.** When adding a panel that pulls from a metric series exposed by a *different* service than the dashboard's host (e.g. a redis panel on a dashboard served by reveried, where `redis_*` series live on the redis exporter, not on reveried's `/metrics`), the browser will hit same-origin `/metrics` and silently get nothing back — graceful-degrade hides the bug and the panel ships flat. Iter 11 shipped a redis HTML panel against reveried's `/metrics`, which has no `redis_*` series; iter 12 had to add a server-side proxy route on reveried that forwards to the redis exporter so the browser fetch stays same-origin. **Rule:** before adding any cross-exporter panel, `curl -s http://<dashboard-origin>/metrics | grep <expected_metric_prefix>` and confirm at least one matching series exists. If it doesn't, either (a) add a server-side proxy route on the dashboard host that forwards to the real exporter, or (b) move the panel to a Grafana dashboard that scrapes both exporters via Prometheus. Never rely on graceful-degrade to mask a missing data source — silent empty panels are indistinguishable from a broken metric pipeline at 3am.
10. **DCGM exporter is fundamentally incompatible with WSL2 — fall back to `utkuozdemir/nvidia_gpu_exporter` and DO NOT bind-mount `nvidia-smi`.** `nvidia/dcgm-exporter` boots, scrapes once, then crashes (or returns empty) on WSL2 because it reads `/sys/bus/pci/devices/<bdf>/local_cpulist` to compute NUMA affinity — that sysfs node does not exist on WSL2's synthetic GPU passthrough (`/sys/bus/pci/devices/` is empty for the GPU; it shows up under `/sys/class/drm` only). Logs read `failed to read local_cpulist: no such file or directory` and the `/metrics` endpoint either 500s or returns the Go runtime metrics with zero `DCGM_*` series. There is no flag to disable the cpulist read — it is hard-coded in the dcp-link topology probe. Do not waste time mounting `/sys` read-write or shimming the file; the next probe (PCIe link width) fails the same way. **Fallback:** `docker run -d --name nvidia_gpu_exporter --restart unless-stopped --gpus all -p 9835:9835 utkuozdemir/nvidia_gpu_exporter:1.4.1` — pure-Go, shells out to `nvidia-smi --query-gpu=...` over NVML, exposes `nvidia_smi_*` series (utilization, memory, temp, power, fan, clocks). **Critical:** do NOT add `-v /usr/bin/nvidia-smi:/usr/bin/nvidia-smi:ro` — the `--gpus all` flag already injects the correct nvidia-smi from the host driver bundle via the nvidia-container-runtime, and bind-mounting the WSL2 host binary on top of it shadows the container's libc-compatible shim with a Windows-side ELF that segfaults on first invocation (the host `/usr/bin/nvidia-smi` on WSL2 is a wrapper that execs `/mnt/c/Windows/System32/lxss/lib/nvidia-smi`, which is not a valid Linux binary inside the container). Verify with `curl -s localhost:9835/metrics | grep -c '^nvidia_smi_'` — expect ≥20 series. Then add the scrape job to prometheus.yml and reload TWICE per pitfall #11. This bit iter 17 and burned ~40 minutes on dcgm before falling back; the utkuozdemir image worked first try with the correct flag set.
12. **`RUST_LOG` / `EnvFilter` directives are per-crate and silently drop spans from subcrates you forgot to list.** `tracing_subscriber::EnvFilter::from_env("RUST_LOG")` parses directives like `reveried=info` as a scope rooted at exactly that crate's module path — spans emitted from any *other* crate in the workspace (e.g. `reverie_store::http::metrics::track`) are evaluated against the global default level (usually `error` or `off`) and dropped before they ever reach the OTLP exporter. The bug looks identical to "tracing layer not wired": daemon boots clean, `/metrics` shows request counters incrementing, Tempo `/api/search` returns `{"traces":[]}`, and there is no error anywhere. Bit iter 18: the `track` middleware on `reverie_store` was instrumented with `#[tracing::instrument]` and the layer was correctly attached, but `RUST_LOG=reveried=info` filtered every span out at the subscriber. **Fix:** enumerate every workspace crate that emits spans in the directive — `RUST_LOG=reveried=info,reverie_store=info,reverie_core=info` (or use a bare default level `RUST_LOG=info,hyper=warn,h2=warn` if you don't need per-crate scoping). **Verify:** `curl -s http://<tempo>:3200/api/search?tags=service.name%3Dreveried | jq '.traces | length'` — expect ≥1 within 10s of issuing a request, not 0. Cross-check with `curl -s http://<tempo>:3200/api/search | jq '.traces[0].spanSets[0].spans | length'` to confirm the span count per trace is non-zero (catches the case where the root span lands but child spans from subcrates are still filtered). Treat any "tracing wired but Tempo empty" symptom as an EnvFilter scope bug until proven otherwise — it is faster to widen the directive and re-test than to audit the layer wiring.
13. **Prometheus `POST /-/reload` needs to fire TWICE before a newly-added scrape job appears.** After editing `prometheus.yml` to add a new `scrape_configs:` job and POSTing to `/-/reload`, the container logs `"Completed loading of configuration file"` and returns 200, but `/api/v1/targets` and `up{job="<new>"}` show nothing — the reload races the scrape scheduler and the first reload returns before the new target is committed to the target manager. The second reload (~3s later) reliably picks it up. Reproduced twice in consecutive iterations (iter 15 dcgm-exporter, iter 16 nvidia_gpu_exporter — both invisible after one reload, both visible after the second). **Fix:** always send the reload twice with a short sleep between, e.g. `curl -fsS -X POST http://localhost:9090/-/reload && sleep 3 && curl -fsS -X POST http://localhost:9090/-/reload`. Verify with `curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].labels.job' | grep <new_job>` before declaring the scrape attached. This is not documented anywhere in the prometheus reload docs and is the single fastest way to waste 20 minutes debugging a perfectly healthy exporter.
14. **Per-minute (`*/1`) cron schedules across multiple subagents will 429 the Anthropic API mid-iteration.** Stacking 5 subagents on `*/1 * * * *` cron triggers fans out concurrent Anthropic API calls every 60s with no jitter; tool calls (Bash, Read, Grep) succeed against the local machine, but the *final assistant turn* — the one that synthesizes the report — fails with HTTP 429 from `api.anthropic.com` because every session competes for the same per-minute token budget on the shared account. The failure mode is misleading: iter logs show successful tool calls right up to the last one, then the session dies with no report written, which looks like "the work didn't happen" when in reality the work did happen and only the summary turn was rate-limited. Bit iter 18 of this skill: the dashboard-manager subagent ran cleanly through all its checks and then 429'd on the writeback. **Fix:** (a) back the cron interval off to `*/10` minimum for any subagent that holds an Anthropic API session, (b) cap `max_output_tokens` on the subagent invocation to reduce per-turn budget pressure, (c) never run `cargo build` (or any other long, output-heavy command) inside a per-minute subagent — the build's stdout balloons the next assistant turn and makes the 429 more likely, move builds to a coord-locked main session instead, and (d) stagger cron offsets across subagents (`*/10 * * * *`, `2-59/10 * * * *`, `4-59/10 * * * *`, …) so they never tick on the same minute. Verify by tailing each subagent's session log for `429` over a full hour after the change; expect zero. Do not try to fix this with retry-on-429 inside the subagent — the retry burns more budget and makes the next tick worse.

## Dashboard audit checklist

Run when the user asks "is my dashboard any good", "audit the dashboard", or any time you're touching a dashboard file (`dashboard/index.html`, `observability/grafana/dashboards/*.json`).

For each panel and for the dashboard as a whole, check:

1. **RED / USE coverage** — for request-driven services, every dashboard needs **R**ate, **E**rrors, **D**uration panels for every public route group. For resource-bound services (queues, pools, connections), every dashboard needs **U**tilization, **S**aturation, **E**rrors per resource. Missing either dimension is a gap.
2. **p50 / p95 / p99, not avg** — averages hide tail latency. Every duration panel must show at least p95 and p99. If the only line is "average response time", that's a finding.
3. **Time range matches the SLO window** — if the SLO is "5xx < 1% over 5m", the panel must use a 5m rolling window, not 1m. Flag mismatches.
4. **Stale or hardcoded queries** — PromQL pointing at metric names that no longer exist (renamed, dropped). Grep the metric names in each panel against the current `metrics.rs` and report any orphans.
5. **Cardinality on the dashboard side** — `topk(50, ...)` on an unbounded label will OOM Grafana. Cap topk values; prefer aggregation by route template.
6. **Saturation panels** — queue depth, in-flight, tab pool busy/free, connection pool utilization. Dashboards without these only show you the symptom (latency) and not the cause.
7. **Error budget burn** — for SLO-tracked services, a panel showing burn rate over 1h and 6h windows. Without this, you find out you're out of budget at the end of the month.
8. **Saturation alerts vs. dashboards** — anything alertable should also be on the dashboard. If an alert fires on a metric that has no panel, the responder has nowhere to look.
9. **Logs panel inline** — Loki/Vector logs panel filtered to the same service+time-range as the metrics panels above it. Click-through from latency spike → log lines is the single biggest "did this dashboard help me" lever.
10. **Health badge** — overall green/yellow/red derived from a small set of weighted signals (error rate, p99, in-flight, queue depth). Flag dashboards where you can't tell at a glance whether the service is healthy.
11. **Dark mode + monospace** — operators read these at 3am. Cosmetic but real.
12. **Auto-refresh** — set to 10–30s for live dashboards. A static dashboard at 3am is a bug.

For each finding: cite the panel (or "missing"), explain what scenario it would fail to surface, and suggest the fix as a small concrete edit (PromQL query, panel JSON, or HTML/JS snippet).

## Mesh observability — multi-service / multi-session

Use when the project is more than one process and you need to see them as a fleet (the revenant + reveried + coord-sessions setup is the canonical example).

1. **Correlation IDs end-to-end** — every inbound request gets a `request_id` (or honors `X-Request-Id` if set). Stamp it into every log line (`tracing` span field) and propagate it on every outbound HTTP / MCP / queue message. Without this you can't follow a single user action across services.
2. **Service identity in every metric and log** — `service`, `instance`, `version` labels (set from `env!("CARGO_PKG_NAME")`, hostname, build version) on every Prometheus metric. In tracing, set them as fmt span fields.
3. **Distributed tracing** — for >2 services on the hot path, add `tracing-opentelemetry` + an OTLP exporter (Jaeger or Tempo). Honor W3C `traceparent` headers in/out. Sample at 100% in dev, 1–10% in prod with always-on for errors.
4. **Cross-service exporter** — for fleets that communicate via filesystem (coord protocol, file queues, drop boxes), build a small in-process scanner task that turns the on-disk state into Prometheus gauges (`<service>_peers_total{role}`, `<service>_inbox_depth{peer}`, `<service>_lock_held_seconds{resource}`). Don't ship a separate exporter binary unless the source service truly can't host it.
5. **Per-role panels on the fleet dashboard** — break out hypervisor vs. worker vs. dashboard-manager (or whatever role taxonomy applies) with separate request rate / queue depth / heartbeat-age panels. A fleet dashboard that only shows totals can't tell you "all the workers are dead but one hypervisor is still alive".
6. **Heartbeat age, not heartbeat count** — `time() - <service>_last_heartbeat_seconds` as the gauge. Counters of heartbeats are useless; the time-since-last-heartbeat is what tells you a peer is dead.
7. **Lock contention panels** — for any mesh that uses a coord/lock protocol, panels showing lock-acquire latency, lock-hold duration histograms, and steal-events counter. Lock contention is the hidden killer in multi-session systems.
8. **Inbox depth + drain rate** — message queues between peers need both, on the same panel, so you can see when production outpaces consumption.
9. **Schema-version gauge** — emit `<service>_schema_version{schema="N"} 1` on boot. When you do a rolling upgrade you can see the mix of versions in the fleet at a glance and know when the upgrade is complete.
10. **Mesh map** — Grafana node-graph panel (or a static HTML force-directed graph for in-house dashboards) showing live edges = active sessions / locks / message flows. Cosmetic but it's the fastest way to onboard a new operator to a complex mesh.

For mesh audits, walk every service in the project and report findings as a matrix:

| Service | Metrics? | Tracing JSON? | /health? | Correlation ID? | Dashboard? | In mesh exporter? |

A blank cell is a finding. Propose the smallest concrete fix per gap, not a rewrite.

## Full-project sweep (default mode when no `crate=` arg)

When invoked with no targeting args, walk the whole workspace and produce a single structured report:

1. **Inventory** — every service / daemon / long-running binary in the project. For each, note: language, framework, current observability layers present (apply the 7-step playbook as a checklist).
2. **Per-service findings** — run the audit checklist (over-request, cardinality, 1s histogram floors, etc.) on each. Cite file:line.
3. **Mesh findings** — run the mesh checklist. Note any cross-service signals that would be valuable but don't exist.
4. **Dashboard findings** — for every dashboard file in the project (`dashboard/`, `observability/grafana/`, `monitoring/`), run the dashboard audit checklist.
5. **Prioritized improvement queue** — order the findings by (blast-radius × ease-of-fix). Top of the queue is what you'd ship in the next iteration if the user said "do the next one".
6. **What's already good** — explicitly call out what's working. Avoid the trap of only listing gaps; the user needs to know what NOT to touch.

Report format: Markdown with one H2 per service, an H3 "matrix" for mesh, an H3 "dashboards" subsection, and a final "next iteration" callout naming the single highest-leverage change.

## Args

- `mode=audit` — only audit, never edit. Output findings as a markdown report.
- `mode=upgrade` — pick the highest-leverage missing layer and implement it (the dashboard-manager loop default).
- `mode=mesh` — focus on cross-service / fleet observability only; skip per-service checklists.
- `mode=dashboard` — focus on dashboard files only; skip code instrumentation.
- `crate=<name>` — target a specific crate in a workspace (e.g. `crate=reverie-store`)
- `path=<dir>` — target a non-Cargo directory
- (no args) — full-project sweep: audit every service + mesh + dashboards, prioritize the queue, and propose the next iteration.
