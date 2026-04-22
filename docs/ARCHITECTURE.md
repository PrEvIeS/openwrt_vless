# Architecture

Technical reference for the three-layer transparent gateway produced by
`install.sh`. For operator-facing usage see `README.md` / `README_RU.md`.
For forward plan see `ROADMAP.md`.

---

## Layers

```
             ┌─────────────────────────────────────────────────────┐
             │ LAN client (phone / laptop / smart TV)              │
             └──────────────────┬──────────────────────────────────┘
                                │ DHCP → gateway = router
                                │ DNS → :53 on router
                                ▼
         ┌──────────────────────────────────────────────────────────┐
         │ OpenWrt router                                           │
         │                                                          │
         │  firewall (nftables)                                     │
         │   ├─ dstnat :53 → LAN_IP:53  ───── Force DNS redirect    │
         │   └─ route traffic → mihomo tun (fake-IP subnet)         │
         │                                                          │
         │  ┌──────────────┐  DoH  ┌───────────────────────────┐    │
         │  │ AdGuard Home │──────►│ Cloudflare / Quad9 / etc. │    │
         │  │  :53         │       └───────────────────────────┘    │
         │  │  filters ads │                                        │
         │  └──────┬───────┘                                        │
         │         │ fake-IP resolved via mihomo :1053              │
         │         │                                                │
         │  ┌──────▼──────────┐                                     │
         │  │ mihomo (nikki)  │                                     │
         │  │  :7890 mixed    │                                     │
         │  │  :1053 DNS      │                                     │
         │  │  tun dev        │─── VLESS+Reality ──► upstream       │
         │  └──────┬──────────┘                                     │
         │         │ non-matching traffic falls through             │
         │         ▼                                                │
         │  ┌────────────────┐                                      │
         │  │ zapret (NFQWS) │ ── DPI bypass (YouTube/TV) ──► WAN   │
         │  └────────────────┘                                      │
         │                                                          │
         │  dnsmasq :54  (LAN host records, DHCP, not resolver)     │
         └──────────────────────────────────────────────────────────┘
```

### Layer 1 — mihomo via nikki

- **Role:** primary transport. Transparent proxy through VLESS+Reality to a
  remote server.
- **DNS mode:** fake-IP — mihomo invents synthetic IPs for matched domains,
  routes them through the tun device, resolves the real destination on the
  other end.
- **Listener ports:** mixed-port `:7890` (manual proxy), DNS `:1053`,
  controller `:9090` (LAN-bound).
- **Config:** `/etc/nikki/profiles/default.yaml` (generated from VLESS URL).

### Layer 2 — zapret (NFQWS)

- **Role:** DPI bypass for services that block or throttle direct traffic
  (YouTube CDN, SmartTV telemetry, Russian-hosted services over VLESS is
  overkill).
- **Mechanism:** Netfilter queue, packet fragmentation / TTL manipulation /
  fake TLS records. No tunneling.
- **Config:** `/etc/config/zapret` — `NFQWS_OPT` starting set in
  `install.sh:DEFAULT_NFQWS_OPT`, tunable via `/opt/zapret/blockcheck.sh`.
- **Parallel to mihomo:** zapret acts on egress AFTER mihomo routing
  decisions; traffic that mihomo leaves alone still benefits from DPI bypass.

### Layer 3 — AdGuard Home

- **Role:** LAN-wide filter. Blocks ads, trackers, telemetry; serves as the
  only DNS resolver for clients.
- **Upstreams:** DoH (Cloudflare, Quad9) by default, configured in post-install
  wizard.
- **Port:** `:53` (LAN-facing). Admin UI on `:3000` by default, operator is
  expected to move to `:8080` and set a password in the first-run wizard.
- **Resolution path for fake-IP:** AGH forwards non-filtered queries to mihomo
  DNS `:1053`, which returns fake-IP for matched domains and real IP for
  bypass rules.

### Force-DNS firewall redirect

- **Role:** catch clients that ignore DHCP-advertised DNS and hardcode
  `1.1.1.1` / `8.8.8.8` / etc.
- **Mechanism:** `nftables` DNAT rule on LAN zone — `udp/tcp dport 53` →
  `LAN_IP:53` (AGH).
- **Limitation:** only catches port-53 traffic. DoH (`:443` to
  `1.1.1.1`) and DoT (`:853`) with hardcoded IPs bypass this. Mitigation is
  out of scope — see `ROADMAP.md §Known limitations`.

### Port map

| Port | Listener | Bind |
|---|---|---|
| 53 (udp/tcp) | AdGuard Home | all LAN |
| 54 (udp/tcp) | dnsmasq (moved from 53) | 127.0.0.1 |
| 1053 (udp) | mihomo DNS | 127.0.0.1 |
| 3000 (tcp) | AdGuard Home admin | all (move to 8080 post-install) |
| 7890 (tcp) | mihomo mixed proxy | 127.0.0.1 |
| 9090 (tcp) | mihomo controller | 127.0.0.1 |

---

## 12-step pipeline

Executed by `install.sh` in order. Steps 1-4 are preflight (no system
mutation). Step 5 creates the rollback snapshot. Steps 6-12 mutate state.

| # | Step | Mutates? | Rollback path |
|---|---|---|---|
| 1 | Preflight: release + arch + pkg manager | No | — |
| 2 | Preflight: extroot + swap | No | — |
| 3 | Preflight: conflicts (rival proxies, `:53` owner, LAN iface, WAN) | No | — |
| 4 | Collect and parse VLESS URL | No | — |
| 5 | Snapshot to `/root/openwrt-mihomo-backup/` (chmod 700) | **Yes** (first) | — |
| 6 | Base packages (`curl`, `block-mount`, USB kmods) | Yes | uninstall.sh |
| 7 | `nikki` feed + mihomo packages | Yes | uninstall.sh |
| 8 | `zapret` via `remittor/update-pkg.sh` | Yes | uninstall.sh |
| 9 | `adguardhome` | Yes | uninstall.sh |
| 10 | Configure profiles, move dnsmasq to `:54`, firewall redirect, service order | Yes | uninstall.sh |
| 11 | Enable + start services (nikki → adguardhome → zapret) | Yes | uninstall.sh |
| 12 | Self-test (ports, daemons, firewall rule) | No (verify only) | — |

### Failure semantics

| Phase | Exit | Behavior |
|---|---|---|
| Steps 1-4 (preflight refuse) | **2** | No writes, no snapshot. Fix environment, re-run. |
| Steps 5-11 (after snapshot, mutation failed) | **1** | Snapshot exists. Installer prints `sh uninstall.sh` hint. **No auto-rollback.** |
| Step 12 (self-test FAIL) | **1** | State kept for diagnostics. Run `uninstall.sh` to revert. |

**Design decision:** no `--force`, no retry loops, no auto-rollback. Symmetry
is enforced at the pipeline level — `uninstall.sh` is the only supported
reversal path.

---

## Snapshot layout

Created at step 5, path: `/root/openwrt-mihomo-backup/` (mode 0700).

```
/root/openwrt-mihomo-backup/
├── snapshot.env          # KV of original UCI values (see below)
├── dhcp                  # /etc/config/dhcp before modification
├── firewall              # /etc/config/firewall before modification
├── network               # /etc/config/network before modification
├── crontab.before        # root crontab at snapshot time
├── packages.before       # opkg list-installed / apk info snapshot
└── installer.log         # timestamped action log
```

`snapshot.env` stores original UCI values for fields the installer rewrites:
- `dhcp.@dnsmasq[0].port`
- firewall zone defaults if changed
- network overrides if LAN iface was auto-detected vs configured

`uninstall.sh` reads `snapshot.env` and applies UCI changes symbolically
(not by blob-replacing config files), so operator edits to unrelated
sections are preserved.

---

## Package manager detection

| OpenWrt | Detector | Manager |
|---|---|---|
| 24.10.x | `/etc/openwrt_release` says `24.10` + `/bin/opkg` exists | `opkg` |
| 25.04 / 25.12 | `/etc/openwrt_release` says `25.` + `/usr/bin/apk` exists | `apk` |

Detection runs in preflight step 1. Installer refuses if neither matches.
Supported releases are listed in `SUPPORTED_RELEASES` (env override: see
README CLI flags).

---

## Service start order

Enforced in step 11 via `/etc/rc.d/` symlink priorities:

```
S90 nikki         ← must be up first (tun device, DNS :1053)
S95 adguardhome   ← depends on nikki DNS upstream
S98 zapret        ← last, acts on egress already shaped by mihomo
```

Crash semantics:
- nikki down → AGH falls back to DoH (set in wizard), but fake-IP subnet
  becomes unreachable; VLESS-routed sites break.
- AGH down → clients lose DNS (Force-DNS redirects them to empty `:53`);
  manual fix: stop Force-DNS firewall rule, restart AGH.
- zapret down → only DPI-protected services degrade (YouTube lag returns).

---

## Design invariants

- **POSIX sh only.** `#!/bin/sh`, no bash extensions. Target is BusyBox ash.
- **`set -eu`** across `install.sh` and `uninstall.sh`. No error swallowing.
- **No network call in preflight steps 1-3.** Step 3's "internet" check is
  opt-out via `--no-internet-check` (TODO — see ROADMAP).
- **No operator prompts after step 4.** Non-interactive mode fails at
  step 4 if VLESS URL is missing instead of blocking mid-pipeline.
- **All generated files are `chmod 600` or `0700` dir** if they contain
  VLESS secrets (UUID, Reality keys).

---

## File layout after install

```
/etc/config/
├── nikki          # nikki UCI (profile selection, service flags)
├── zapret         # zapret UCI (NFQWS_OPT, mode)
├── adguardhome    # AGH UCI
├── dhcp           # modified: @dnsmasq[0].port=54
├── firewall       # modified: +include Force-DNS redirect
└── network        # usually unchanged

/etc/nikki/profiles/default.yaml    # mihomo config, 0600
/etc/AdGuardHome.yaml               # AGH config (generated, bind_port=3000)
/opt/zapret/                        # zapret install tree
/root/openwrt-mihomo-backup/        # snapshot (see above)
```
