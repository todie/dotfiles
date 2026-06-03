#!/usr/bin/env bats
# Behavioral tests for the `cci` CLI (Claude Code Introspect).
# Deterministic: uses $$, pid 1, and a nonexistent pid so it runs anywhere
# (no Claude session or tmux server required). Run: `bats test/cci.bats`.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  # Deploy the chezmoi source (executable_cci) under its real command name.
  install -m 0755 "$REPO/home/dot_local/bin/executable_cci" "$BIN/cci"
  PATH="$BIN:$PATH"
  command -v argc >/dev/null 2>&1 || skip "argc not on PATH"
}

@test "cci --help lists all three subcommands" {
  run cci --help
  [ "$status" -eq 0 ]
  [[ "$output" == *pid* ]]
  [[ "$output" == *alive* ]]
  [[ "$output" == *pane* ]]
}

@test "alive --loose on the current shell pid reports alive" {
  run cci alive --loose "$$"
  [ "$status" -eq 0 ]
  [ "$output" = alive ]
}

@test "alive on a nonexistent pid reports dead (exit 1)" {
  run cci alive 999999
  [ "$status" -eq 1 ]
  [ "$output" = dead ]
}

@test "alive strict on pid 1 is dead — alive but not a claude session" {
  run cci alive 1
  [ "$status" -eq 1 ]
  [[ "$output" == dead* ]]
}

@test "alive --loose on pid 1 is alive — EPERM must not read as dead" {
  run cci alive --loose 1
  [ "$status" -eq 0 ]
  [ "$output" = alive ]
}

@test "pid 1 has no claude ancestor and fails cleanly" {
  run cci pid 1
  [ "$status" -eq 1 ]
}

@test "an unknown subcommand is rejected" {
  run cci bogus
  [ "$status" -ne 0 ]
}
