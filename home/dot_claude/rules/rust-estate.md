---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
  - "**/specs/**"
---
# Rust and spec work on the estate

Before a Rust or LeanSpec change, read `~/.agents/sops/rust-repo-best-practices.md` and `~/.agents/sops/lean-specification-and-rust-best-practices.md`. They hold the `make check` gate, the Clippy restriction floor, the type-driven design rules, the cache conventions and the spec format.

On ceres every cargo call uses `-j 2` (`JOBS=2`). The host is shared.
