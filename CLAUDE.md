# Project Instructions for AI Agents

OpenWrt 24.10.x / 25.04 / 25.12.x transparent gateway installer (mihomo+nikki + zapret + AdGuard Home + Force-DNS).
Pure POSIX shell — BusyBox `ash` on OpenWrt. No bashisms.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->

## Build & Test

No compile / package step — `install.sh` and `uninstall.sh` are POSIX-shell scripts shipped as-is. Quality gates:

```bash
# Lint (POSIX-strict, BusyBox ash target)
shellcheck -s sh install.sh uninstall.sh

# Syntax-only smoke (POSIX, dash is the closest available reference shell)
sh   -n install.sh && sh   -n uninstall.sh
dash -n install.sh && dash -n uninstall.sh

# Unit tests (run with both sh and dash, both must pass)
sh   tests/test_vless_url.sh   && dash tests/test_vless_url.sh
sh   tests/test_urldecode.sh   && dash tests/test_urldecode.sh
sh   tests/test_state_file.sh  && dash tests/test_state_file.sh
sh   tests/test_parse_args.sh  && dash tests/test_parse_args.sh
```

CI gate: `.github/workflows/ci.yml` runs shellcheck + `sh -n` / `dash -n` + every `tests/test_*.sh` on each push/PR.

End-to-end is hardware-only (router under `ssh root@192.168.1.1`) — no CI.

## Architecture Overview

Three transparent-proxy layers stacked on a single OpenWrt router. Detailed mermaid diagrams in `docs/ARCHITECTURE.md`.

```
LAN client ─[:53 / TCP / UDP]→ fw4 (Force-DNS DNAT + tproxy mark 0x81)
              │                  │
              │                  ├→ AdGuard Home :53 ─→ mihomo :1053 (fake-IP /16)
              │                  │                    └→ DoH upstream (Cloudflare)
              │                  └→ mihomo tproxy :7891 ─routes via geosite/geoip─→ VLESS+Reality VPS
              │                                          │
              │                                          └→ DIRECT path → zapret NFQWS → ISP
```

**Layer 1 — mihomo (via [nikki](https://github.com/nikkinikki-org/OpenWrt-nikki)):** primary VLESS+Reality transport. fake-IP DNS, redir_tun mode. Profile at `/etc/nikki/profiles/main.yaml`, UCI mixin pinned by `install.sh` to override package defaults that bind `[::]:1053` and `auto-detect-interface=false`.

**Layer 2 — zapret ([remittor/zapret-openwrt](https://github.com/remittor/zapret-openwrt)):** NFQWS DPI bypass for the DIRECT path. UCI keys are uppercase (`NFQWS_OPT`, `MODE_FILTER`); writes must be followed by `/opt/zapret/sync_config.sh`. UCI silently truncates multi-line values at `\n` — strategy is concatenated with spaces, `--new` separates filter sections.

**Layer 3 — AdGuard Home:** LAN-wide ad/tracker/telemetry filter. Bound to `:53`, web-wizard at `:3000` (operator moves to `:8080`). Config at `/etc/adguardhome/adguardhome.yaml` (UCI key `config_file`).

**Force-DNS firewall redirect:** nftables DNAT in LAN-zone — `udp/tcp dport 53` → `LAN_IP:53`. Catches clients with hard-coded `1.1.1.1:53` / `8.8.8.8:53`. Only `:53`; DoH/DoT pass through.

Routing rules in mihomo profile (first match wins): LAN→DIRECT, YouTube→`YOUTUBE` selector (default VLESS-REALITY), `geosite:ru-available-only-inside`→DIRECT, `.ru`/`.рф`/`.su`/`geoip:RU`→DIRECT, `geosite:ru-blocked`→PROXY, MATCH→`FINAL` selector.

Rule data: [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) `release` branch — pre-downloaded by `install.sh` before mihomo first start (chicken-and-egg: empty cache blocks startup DNS).

## Conventions & Patterns

- **POSIX shell only.** `set -eu`. Verify with `dash -n` and `shellcheck -s sh` before considering a change ready.
- **Constants at the top** of `install.sh` (lines 1–110): supported releases/arches, file paths, UCI keys, default NFQWS strategy. Change in one place.
- **`log()` / `warn()` / `die()`** for output — never bare `echo`. `die()` prints uninstall hint after `INSTALL_STARTED=1`.
- **`_set_if_empty VAR VALUE`** preserves CLI override priority. URL parser must call this, not raw assignment.
- **Idempotent steps.** Each pipeline step writes a marker into `/etc/openwrt-setup-state`; re-runs skip completed steps unless `--force-config`.
- **Strict fail-fast.** No `--force` flag, no retry loops, no auto-rollback. Preflight refuse → exit 2 (no mutations); mid-pipeline error → exit 1 with `sh uninstall.sh` hint.
- **No AI slop.** Dry technical tone, no "comprehensive solution" / "robust" / "production-ready" hedging. Russian on user-facing paths, English on internal/technical — match the file you're editing.
- **Comments only when WHY is non-obvious** (DPI quirks, UCI truncation, procd argv splitting, package init.d overrides). Don't narrate WHAT the code does.
- **CHANGELOG.md is immutable** for past releases. On doc sweeps, update README/ROADMAP/CONTRIBUTING/ARCHITECTURE — never rewrite values inside an already-shipped CHANGELOG entry.
- **Privacy-first git history.** No vendor / device names in commit messages. Aggressive history rewrites (force-push to single commit) are acceptable when identity changes.
- **`refs/` is read-only.** Contains git clones of upstream reference repos (mihomo-proxy-ros, russia-v2ray-rules-dat). Do not edit; do not commit changes inside.
