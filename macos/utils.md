# Candidate utils — brew-update batch 2026-07-25

Full menu from a `brew update` batch of new formulae/casks, triaged for Europa
(M5 Max, local-MLX, Claude Code power user, agentic harnesses, 92 repos, voice/ASR).
Iterate: move a `deferred`/`skipped` entry up to **wired** by adding it to
`home/dot_Brewfile` (re-bundles automatically on next `chezmoi apply`).

## ✅ Wired into ~/.Brewfile

| Pkg | Type | What |
|-----|------|------|
| rapid-mlx | formula | Fast local AI engine for Apple Silicon, OpenAI-compatible API |
| gita | formula | Manage multiple git repos with sanity |
| apm | formula | Dependency manager for AI agent configuration |
| dskditto | formula | Ultra-fast duplicate file finder TUI |
| droast | formula | Opinionated Dockerfile linter |
| humanbound | formula | Adversarial security testing engine/SDK/CLI for AI agents |
| pixtuoid | formula | Terminal pixel-art office for AI coding agents (surprise) |
| kimi-code | formula | Kimi 3 AI coding agent for terminal |
| openwhispr | cask | Privacy-first voice-to-text with AI agents |
| koe | cask | Zero-GUI voice input tool |
| sessionwatcher | cask | Menu-bar monitor for AI coding-assistant usage + limits |
| claude-status-bar | cask | Menu-bar status indicator for Claude Code |
| clarc | cask | Desktop client for Claude Code |
| hermes-desktop | cask | Open-source desktop AI agent |
| codexia | cask | GUI/toolkit for Codex CLI and Claude Code |
| neodisk | cask | Read-only disk-space visualiser |
| pastebot@2 | cask | Clipboard-history workflow app |
| kimi | cask | Kimi 3 desktop AI chat assistant (v3.1.5) |
| cate | cask | Infinite zoomable canvas: editor/terminal/browser (surprise) |

## 🕗 Deferred — plausible, not wired yet (bump when wanted)

| Pkg | Type | What | Why deferred |
|-----|------|------|--------------|
| lunarr | formula | Self-hosted media server / Plex alt | personal media, not core |
| moonfin | cask | Jellyfin/Emby streaming client | pairs w/ lunarr; personal |
| changes | cask | Git GUI | you're CLI-first (gita covers multi-repo) |
| block-buzz | cask | Workspace for humans + AI agents | overlaps cate/onit; try one |
| onit-sidekick | cask | AI chat panel | overlaps hermes-desktop |
| deepline | formula | CLI for Deepline data enrichment | unclear fit |
| nullhub | formula | Management console for the Null ecosystem | unknown ecosystem |
| dnclient-server | cask | Nebula P2P VPN daemon | you use Tailscale |
| opendisplay | cask | Second-display for iPhone/iPad | situational |
| billy | cask | Invoice manager | ops, not dev |

## ⛔ Skipped — off-target for this machine/user

| Pkg | Type | Why |
|-----|------|-----|
| kimi-cli | formula | deprecated upstream (disabled 2027-01-17) — use kimi-code |
| kimis | cask | Misskey (fediverse) client — NOT Moonshot Kimi |
| fastani | formula | whole-genome ANI (bioinformatics) |
| wild | formula | Linux linker (not macOS) |
| virtiofsd | formula | Linux virtio-fs VM backend |
| wgsl-analyzer | formula | WGSL/WESL LSP — only if doing WebGPU shaders |
| roslynpad | cask | C# editor/runner |
| sogouinput | cask | Chinese input method |
| gamehub | cask | Windows/Steam game compat layer |
