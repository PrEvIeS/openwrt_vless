# Changelog

All notable changes to this project are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/):
- **MAJOR** — breaking change in CLI flags, UCI layout, or snapshot format.
- **MINOR** — new pipeline step, new optional flag, new supported release.
- **PATCH** — bug fixes, docs, NFQWS defaults.

Entries are written by hand per release tag. No commit-message autogeneration.

---

## [Unreleased]

_Nothing yet._

---

## [0.2.0] — 2026-04-22

### Added
- `ROADMAP.md` — near / mid / long-term plan, testing matrix, release policy,
  contribution rules.
- `LICENSE` (MIT), `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`.
- `docs/ARCHITECTURE.md` — traffic flow diagram, 12-step pipeline detail,
  port map, snapshot layout.
- `docs/TROUBLESHOOTING.md` — cheatsheet for preflight refuses, `:53`
  conflicts, YouTube lag, AGH wizard port collision, mihomo boot failures.
- README IPv6 section (EN + RU) — documents v4-only routing and the
  LAN-side v6 disable recipe. Full `--ipv6 {bypass,drop,route}` flag
  stays on ROADMAP.
- `.github/ISSUE_TEMPLATE/` and `.github/PULL_REQUEST_TEMPLATE.md`.
- `.github/workflows/ci.yml` — `shellcheck -s sh`, dash/sh `-n` syntax
  smoke, and VLESS URL parser fixture tests on push + PR.
- `tests/test_vless_url.sh` + `tests/fixtures/vless_urls/{valid,broken}/` —
  fixture-based tests for `parse_vless_url()` (5 valid + 4 broken cases).
- `.beads/` — issue tracker config and hooks.
- `AGENTS.md`, `CLAUDE.md` — agent onboarding and beads workflow notes.

### Changed
- `.gitignore`: exclude `refs/` (local reference clones).
- `install.sh`: gate `main "$@"` behind `INSTALL_SH_TEST_MODE` so the
  script can be sourced by the test runner without executing the pipeline.
  Quick-start wget flow is unaffected (env var unset by default).

### Fixed
- `install.sh`: rewrite `_urldecode` as pure-POSIX loop using
  `printf "\\$(printf '%03o' "0x$hh")"` — the prior `printf '%b' '\xHH'`
  path failed on dash (GH Actions /bin/sh), which does not interpret `%b`
  hex escapes. BusyBox ash and macOS bash-as-sh were unaffected.
- `uninstall.sh`: `stop_cron` no-op when `# mihomo-gateway` marker absent;
  preflight tightening in `install.sh`.

---

## [0.1.0] — 2026-04-22

### Added
- Initial three-layer OpenWrt installer:
  - mihomo via nikki (VLESS+Reality, fake-IP DNS, rule-based routing).
  - zapret via remittor (DPI bypass, YouTube/SmartTV).
  - AdGuard Home (LAN filter, DoH upstreams).
  - Force-DNS firewall redirect for hard-coded `:53`.
- 12-step pipeline with preflight refuse, snapshot, symmetric `uninstall.sh`.
- Auto-detection of `opkg` (OpenWrt 24.10.x) / `apk` (25.x).
- CLI flags: `--vless-url`, per-field overrides, `--no-{zapret,adguard,
  force-dns,i18n}`, `--force-config`, `--non-interactive`.
- Supported releases: 24.10.0-2, 25.04.0, 25.12.0-2.
- Reference hardware: Netis N6.
- Bilingual docs: `README.md` (short), `README_RU.md` (full).

[Unreleased]: https://github.com/PrEvIeS/openwrt_vless/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/PrEvIeS/openwrt_vless/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/PrEvIeS/openwrt_vless/releases/tag/v0.1.0
