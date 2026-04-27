<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-27 | Updated: 2026-04-27 -->

# tests

## Purpose
POSIX-shell unit tests for `install.sh` internals. Sources `install.sh` with `INSTALL_SH_TEST_MODE=1` to skip `main()`, then exercises individual functions against fixtures or inline assertions. Every test must pass under both `sh` and `dash` — CI runs them twice.

## Key Files

| File | Description |
|------|-------------|
| `test_vless_url.sh` | Fixture-based tests for `parse_vless_url()`. Iterates `fixtures/vless_urls/valid/*.url` (parser must succeed and produce KEY=VALUE pairs matching `*.expect`) and `fixtures/vless_urls/broken/*.url` (parser must die). |
| `test_urldecode.sh` | Unit tests for `_urldecode()` — `%XX` decoding + `+` → space conversion (URL fragments). |
| `test_state_file.sh` | Idempotency state-file primitives — write/read of `/etc/openwrt-setup-state` markers (uses tmp dir override). |
| `test_parse_args.sh` | CLI flag parsing. Asserts override priority, `--no-adguard` without `--no-force-dns` → refuse, unknown flag → exit 2. |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `fixtures/` | Test input data (see `fixtures/AGENTS.md`) |

## For AI Agents

### Working In This Directory

- **No bash.** Every test must run under BusyBox `ash` (proxy: `sh` + `dash` on Linux CI). `set -u` only — `set -e` would mask intentional failure paths.
- Tests source `install.sh` via `INSTALL_SH_TEST_MODE=1`. `main()` is gated on this flag — re-check the gate in `install.sh` if you add a new entry point.
- Pass/fail accounting via two integers (`pass`, `fail`) and `log_pass` / `log_fail` helpers. Final exit: `[ "$fail" -eq 0 ]`.
- Adding a new fixture: drop `NN_name.url` (one line) plus `NN_name.expect` (KEY=VALUE per line) into `fixtures/vless_urls/valid/` or `fixtures/vless_urls/broken/`. The runner picks them up automatically.
- Adding a new test file: add a step to `.github/workflows/ci.yml` `unit-tests` job (run with both `sh` and `dash`).

### Testing Requirements

```sh
# Run individual test
sh   tests/test_vless_url.sh
dash tests/test_vless_url.sh

# Run all (matches CI)
for t in tests/test_*.sh; do sh "$t" && dash "$t" || exit 1; done
```

Exit 0 = all pass, non-zero = any failure.

### Common Patterns

- Partial assertions: `*.expect` lists only the keys the test cares about — extra globals in `install.sh` after parse are ignored.
- `_dump()` helper pattern: subshell + `set` to capture globals after a function call without polluting the runner's environment.

## Dependencies

### Internal
- `../install.sh` — sourced under test mode. Function signatures are the contract.

### External
- `dash` — POSIX-strict reference shell on CI (closest available proxy for BusyBox `ash`).

<!-- MANUAL: -->
