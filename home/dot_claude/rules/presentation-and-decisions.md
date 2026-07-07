# Presentation & Decision Rules

How to surface long-form material and how to extract decisions. Binds the AGENT.

## Long-form goes to $EDITOR, not the terminal
When presenting **long-form content for the operator's consideration** — design
proposals, research write-ups, RFCs, multi-section plans, migration docs, any
artifact >~40 lines meant to be *read and judged* (not skimmed) — **write it to a
file and open it in `$EDITOR`** rather than dumping it into the terminal.

- Open in the **host editor** (WSL): `zedw <path>` (Zed) or `code <path>` (VS
  Code). Prefer `$EDITOR` if set, else `zedw`.
- The terminal/chat gets only a **short orientation**: what it is, where it lives
  (file path + PR link if committed), and the decisions you need (see below).
- Reserve inline terminal prose for short answers, status, and summaries — the
  long form is for the editor where it can actually be read and annotated.

## Open decisions = interview mode (forced)
For **open decisions** — any fork where the operator's choice changes what you do
next — **use the `AskUserQuestion` tool (interview mode).** Do NOT enumerate the
decisions as prose bullets and ask for a free-form reply.

- One `AskUserQuestion` question per decision; concrete, mutually-exclusive
  options; recommend one (first, marked "Recommended") when you have a lean.
- Batch related decisions into a single `AskUserQuestion` call (up to 4) rather
  than scattering them across messages.
- **No exceptions for "small" or closing forks.** A binary or end-of-turn
  "want me to X, or Y?" is still an open decision — pose it via `AskUserQuestion`,
  never as a trailing prose question. Default to interview mode for *every*
  multipart/decision questionnaire. The only prose-question case is a single
  genuinely open-ended clarification with no enumerable options.
- A document's "Open decisions" section is a **prompt to interview**, not a place
  to park questions and move on.

**Why:** long form drowns in a terminal and decisions buried in prose get a vague
reply or none. Editor for reading, structured interview for choosing — so the
operator's judgment is captured cleanly, not reconstructed from a wall of text.
