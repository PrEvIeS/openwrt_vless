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

---

## [0.3.0] — 2026-04-27

### Added
- 16-step pipeline (was 12 в 0.2.0): шаги 0 (first-time setup), 10
  (luci-theme-argon), 11 (luci-app-statistics + collectd), 12 (SQM cake),
  13a-e (split configure phase). Каждый шаг идемпотентен через state-file.
- `install.sh` — idempotent state-file `/etc/openwrt-setup-state`. Повторный
  запуск пропускает завершённые шаги; `--force-config` сбрасывает state.
- `install.sh` — UCI `nikki.mixin.*` pinning (`dns_listen=127.0.0.1:1053`,
  `api_listen=127.0.0.1:9090`, `tproxy_port=7891`, `redir_port=7892`,
  `outbound_interface=wan`, `api_secret=132019`, `ipv6=0`). Без этого
  пакетный default `dns_listen='[::]:1053'` тихо ломает UDP DNS к AGH.
- `install.sh` — geosite/geoip pre-download из `runetfreedom/v2ray-rules-dat`
  (`ru-blocked` + `ru-available-only-inside`) через `curl --resolve` ДО
  старта nikki. Решает chicken-and-egg DNS-bootstrap'а mihomo.
- `install.sh` — fallback на GitHub-релизы tarball'ом если nikki feed
  заблокирован DPI (`*.pages.dev` SNI-блок у RU ISP).
- `install.sh` — hotplug-скрипт `/etc/hotplug.d/net/30-nikki-fakeip` —
  `ip route replace 198.18.0.0/16 dev nikki` при `INTERFACE=nikki`.
- NFQWS-стратегия v2: 7 секций через `--new` (Google-hostlist `fake`+TLS,
  multisplit, hostfakesplit, TCP/80, QUIC, discord/stun, CF-alt-ports).
  Single-line concat — UCI `set` режет значение на первом `\n`.
- Cudy TR3000 v1 как второй reference HW (filogic/aarch64). Netis N6
  остаётся первым.
- `tests/test_urldecode.sh` (20 проверок) — `_urldecode()` POSIX behavior.
- `tests/test_state_file.sh` (13 проверок) — state-file идемпотентность.
- `tests/test_parse_args.sh` (20 проверок) — CLI flag parsing, конфликты,
  exit codes.
- VLESS URL fixtures расширены: `valid/{06_no_port,07_ipv4_server,08_minimal}`.
- `.github/workflows/ci.yml` — отдельный `unit-tests` job, прогоняет все
  4 тест-скрипта на `sh` и `dash`.

### Changed
- `install.sh` — `proxy-groups → YOUTUBE` теперь использует
  `proxies: [VLESS-REALITY, DIRECT]` (был `[DIRECT, VLESS-REALITY]`).
  Default DIRECT ломал YouTube на Smart TV (Yandex Station, Tizen,
  WebOS, Android TV) — RU ISP DPI обрывает TCP/443 к youtube.com,
  TV YT-app без QUIC fallback виснет на TLS handshake. ПК-браузер
  не страдал из-за QUIC. Selector сохранён, ручной toggle через
  mihomo UI/API работает, выбор кэшируется в `/etc/nikki/cache/cache.db`.
- `install.sh` — zapret UCI keys мигрированы на UPPERCASE (`NFQWS_OPT`,
  `MODE_FILTER` etc.) — remittor/zapret-openwrt читает только UPPERCASE.
  После UCI write обязателен `/opt/zapret/sync_config.sh` — иначе runtime
  читает старые `/opt/zapret/config`.
- `install.sh` — AGH config-path `/etc/adguardhome/adguardhome.yaml` (было
  `/opt/adguardhome/AdGuardHome.yaml`). Пакетный init.d читает только
  `/etc/adguardhome/`. UCI ключ `config_file` (был `workdir`).
- `install.sh` — nikki profile path `/etc/nikki/profiles/main.yaml` (было
  `/etc/nikki/run/profiles/main.yaml`). `chmod 600`.
- `install.sh` — mihomo `fake-ip-filter` расширен на `+.ru/+.рф/+.su/+.by/
  +.kz` + `+.yandex.net` + `www.youtube.com`. Без этого `.ru`-сайты получали
  fake-IP, шли по DIRECT-rule на 198.18 и теряли TLS.
- `install.sh` — DNS-policy: Cloudflare DoH (`cloudflare-dns.com` / `1.1.1.1`)
  для `.ru/CIS` (был Yandex DoH).
- `install.sh` — `zapret-hosts-user.txt` расширен на 16 YouTube/Google-CDN
  доменов (было 10).
- shellcheck cleanup: SC2015 (`a && b || c` → `if/then/fi`), SC2086
  (whitelist для intentional word-split в curl `--resolve`).
- README / README_RU / ROADMAP / CONTRIBUTING / docs/ARCHITECTURE
  синхронизированы с текущим состоянием installer'а: 16-step pipeline,
  правильные пути, UCI keys, NFQWS strategy, runetfreedom geosite.
- `docs/ARCHITECTURE.md` — переписан с нуля на mermaid-диаграммы (5 штук:
  слои, DNS flow, routing rules, NFQWS pipeline, install sequence).

### Removed
- `install_youtube_mss_clamp` функция и связанная инфраструктура
  (`/etc/init.d/yt-mss-clamp`, `/usr/libexec/openwrt-vless/youtube-mss.sh`,
  cron `*/30`, nft table `inet yt_mss`). Static MSS=88 clamp на SYN к
  IP YouTube не работал — `fw4 mangle_postrouting` на pppoe-wan делает
  свой MSS-clamp `set rt mtu` (=1452), который перезаписывает наш
  `set 88` в output mangle. Реальная причина SmartTV-проблемы была
  в YOUTUBE selector, не в MTU.

### Fixed
- `install.sh` — runtime correctness на чистом OpenWrt 25.12.x: UCI multi-line
  truncation (NFQWS_OPT теперь single-line concat), nikki mixin pinning,
  AGH fake-IP route через hotplug, расширенный hostlist.

### Documentation
- `docs/TROUBLESHOOTING.md` — секция "YouTube не работает на Smart TV"
  с диагностикой через mihomo `/proxies/<group>` + `/connections` API
  и hot-fix командами.

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

[Unreleased]: https://github.com/PrEvIeS/openwrt_vless/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/PrEvIeS/openwrt_vless/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/PrEvIeS/openwrt_vless/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/PrEvIeS/openwrt_vless/releases/tag/v0.1.0
