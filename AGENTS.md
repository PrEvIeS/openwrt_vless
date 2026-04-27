<!-- Generated: 2026-04-27 | Updated: 2026-04-27 -->

# openwrt_script — Agent Instructions

OpenWrt 24.10.x / 25.04 / 25.12.x transparent gateway installer.
Three layers: **mihomo** (via nikki, VLESS+Reality) + **zapret** (NFQWS DPI bypass) + **AdGuard Home** + **Force-DNS** firewall redirect.
BusyBox `ash` compatible POSIX shell — no bashisms.

Operator docs: `README.md` (EN orientation) / `README_RU.md` (primary).
Architecture: `docs/ARCHITECTURE.md`. Forward plan: `ROADMAP.md`. Failure modes: `docs/TROUBLESHOOTING.md`.

## Key Files

| File | Description |
|------|-------------|
| `install.sh` | 16-step installer pipeline. Idempotent via `/etc/openwrt-setup-state`. ash-only, `set -eu`. |
| `uninstall.sh` | Symbolic UCI restore from `snapshot.env`, stop+disable services. extroot/swap untouched. |
| `README.md` | English orientation, CLI flags, pipeline summary, runetfreedom rule lists. |
| `README_RU.md` | Primary Russian operator manual — extroot/swap prep, full troubleshooting. |
| `CHANGELOG.md` | Immutable per-release log. Do **not** rewrite past releases on doc sweeps. |
| `ROADMAP.md` | Forward plan. IPv6 policy, hardening, additional layers. |
| `CONTRIBUTING.md` | PR / issue / commit workflow. |
| `SECURITY.md` | Disclosure policy. |
| `LICENSE` | MIT. Third-party packages keep upstream licenses. |
| `CLAUDE.md` | Project-level AI agent instructions (build/test/conventions). |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `docs/` | Architecture & troubleshooting (see `docs/AGENTS.md`) |
| `tests/` | POSIX-shell unit tests + fixtures (see `tests/AGENTS.md`) |
| `.github/` | CI workflows + issue/PR templates (see `.github/AGENTS.md`) |
| `refs/` | External reference repos (git clones — read-only, **do not edit**). |

## For AI Agents

### Working In This Repo

- All shell code targets **BusyBox ash on OpenWrt**. Verify with `dash -n` / `shellcheck -s sh`. No `bash`-only constructs (no `[[ ]]`, no arrays, no `local` outside functions, no process substitution).
- `install.sh` constants live at the top (lines 1–110). UCI config keys, default NFQWS strategy, supported releases/arches all there — change in one place, not scattered.
- Idempotency invariant: re-running `install.sh` skips completed steps unless `--force-config`. Each new step must update `SETUP_STATE_FILE`.
- Strict fail-fast: no `--force`, no retry loops, no auto-rollback. Preflight refuses → exit 2; mid-pipeline error → exit 1 with `sh uninstall.sh` hint.
- DPI / DNS quirks the code works around are documented in user memory under `~/.claude/projects/-Users-denn-PhpstormProjects-openwrt-script/memory/`. Read those before touching `configure_nikki` / `configure_zapret` / `install_dns_interception`.

### Build & Test

```sh
shellcheck -s sh install.sh uninstall.sh    # POSIX-strict lint
sh -n install.sh && sh -n uninstall.sh      # syntax-only smoke
dash -n install.sh && dash -n uninstall.sh  # POSIX-strict syntax
sh tests/test_vless_url.sh                  # parser fixtures
sh tests/test_urldecode.sh                  # _urldecode unit tests
sh tests/test_state_file.sh                 # idempotency
sh tests/test_parse_args.sh                 # CLI flag parsing
```

CI (`.github/workflows/ci.yml`) runs all of the above on each push/PR via `sh` and `dash`.

### Common Patterns

- `log() / warn() / die()` for output — never raw `echo`. `die()` switches to "Откат: sh uninstall.sh" hint after `INSTALL_STARTED=1`.
- `_set_if_empty VAR VALUE` — CLI override > URL value > default. URL parser must not overwrite override flags.
- UCI writes are followed by `uci commit <pkg>` and (for zapret) `/opt/zapret/sync_config.sh`. Multi-line UCI values silently truncate at first `\n` — concatenate with spaces.
- Russian comments / log strings on user-facing paths; English on technical/internal. Match prevailing tone in the file you're editing.

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file ops to avoid hanging on confirmation prompts. Some shells alias `cp`/`mv`/`rm` to `-i` mode.

```bash
cp -f src dst                  # NOT: cp src dst
mv -f src dst                  # NOT: mv src dst
rm -f file                     # NOT: rm file
rm -rf dir                     # NOT: rm -r dir
cp -rf src dst                 # NOT: cp -r src dst

scp -o BatchMode=yes ...        # fail instead of prompting
ssh -o BatchMode=yes ...        # fail instead of prompting
apt-get -y ...
HOMEBREW_NO_AUTO_UPDATE=1 brew ...
```

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

<!-- MANUAL: Manually added notes are preserved on regeneration -->
