# OpenWrt Mihomo Gateway Installer

Three-layer transparent gateway for **OpenWrt 25.12.2** on any supported
architecture (MIPS / aarch64 / arm / x86_64 variants — see
`SUPPORTED_ARCHES`):

- **mihomo** via [`nikki`](https://github.com/nikkinikki-org/OpenWrt-nikki)
  — VLESS+Reality for RU-blocked resources, fake-IP DNS, rule-based routing
- **zapret** via [`remittor`](https://github.com/remittor/zapret-openwrt)
  — DPI bypass for YouTube / SmartTV (no VPN, native ping)
- **AdGuard Home** — LAN-wide ad/tracker/telemetry filter with DoH upstreams
- **Force-DNS firewall redirect** — intercepts hard-coded DoT/:53 from devices

> **Primary documentation is Russian:** [README_RU.md](README_RU.md).
> This English page is a short orientation only.

---

## Requirements

- OpenWrt **25.12.2** exactly (installer refuses other releases)
- `DISTRIB_ARCH` in the installer's `SUPPORTED_ARCHES` allowlist (MIPS /
  aarch64 / arm / x86_64 variants; nikki + zapret detect the actual arch)
- **extroot on USB/SD/NVMe** mounted at `/overlay` (≥ 2 GiB) — mandatory
- **Active swap partition** (≥ 1 GiB recommended 1.5 GiB)
- ≥ 200 MB RAM, root SSH, working internet
- Clean OpenWrt (no `xray` / `sing-box` / `mihomo` / `passwall*` / `podkop`
  running; `:53` held by stock `dnsmasq` or free)
- **VLESS+Reality URL** of the form
  `vless://UUID@host:port?type=tcp&encryption=none&security=reality&pbk=...&fp=chrome&sni=...&sid=...&flow=xtls-rprx-vision#label`

See [README_RU.md](README_RU.md) §Требования for the full list and extroot
setup (Stage 3).

---

## Quick start

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/PrEvIeS/openwrt_vless/main/install.sh
sh /tmp/install.sh
```

Interactive mode prompts only for the VLESS URL. Non-interactive example:

```sh
sh install.sh --non-interactive \
    --vless-url 'vless://UUID@host:443?type=tcp&security=reality&pbk=KEY&sni=www.google.com&sid=DEADBEEF&flow=xtls-rprx-vision&fp=chrome#label'
```

Override priority: `--vless-*` CLI flag > URL value > fallback default.

---

## CLI flags (summary)

| Flag | Purpose |
|---|---|
| `--vless-url URL` | Full VLESS Reality URL (required unless full `--vless-*` override set) |
| `--vless-server/port/uuid/pubkey/sid/sni/flow/fp/...` | Override individual fields |
| `--nfqws-opt STR` | Custom zapret NFQWS strategy (default = starter from plan §5.7) |
| `--no-zapret` / `--no-adguard` / `--no-force-dns` / `--no-i18n` | Skip a layer |
| `--force-config` | Overwrite existing `AdGuardHome.yaml` / nikki profile / snapshot |
| `--non-interactive` | Fail instead of prompting |
| `-h`, `--help` | Show usage |

---

## 12-step pipeline

1. Preflight — release + architecture
2. Preflight — extroot + swap
3. Preflight — conflict probes (rival proxies, `:53` owner, LAN iface)
4. Collect & parse VLESS URL
5. Pre-install state snapshot (`/root/openwrt-mihomo-backup/`, chmod 700)
6. Base packages (curl, block-mount, usb-storage, …)
7. `nikki` feed + mihomo packages
8. `zapret` via `remittor/update-pkg.sh`
9. `adguardhome`
10. Configure profiles, `dnsmasq`→:54, firewall, service order
11. Enable + start services (`nikki` → `adguardhome` → `zapret`)
12. Self-test (ports, daemons, firewall rule)

---

## Failure modes — strict fail-fast

| Phase | Exit code | What happens |
|---|---|---|
| Preflight refuse (wrong release / arch / extroot / conflict) | **2** | nothing written, run again after fixing |
| Error after snapshot (mutations begun) | **1** | installer prints `sh uninstall.sh` hint, no auto-rollback |
| Self-test FAIL | **1** | per-check report, state kept, run uninstall to revert |

No `--force` flag. No retry loops. No auto-detect of subscription format.

---

## Post-install (manual)

1. Open AdGuard Home wizard at `http://<LAN_IP>:3000` — set admin port to
   `:8080`, DNS bind to all interfaces `:53`, create password.
2. If YouTube is slow or blocked, tune zapret strategy:
   ```sh
   service zapret stop
   /opt/zapret/blockcheck.sh
   # → update NFQWS_OPT in LuCI → Services → Zapret
   ```

Full walkthrough: [README_RU.md](README_RU.md) §Пост-установка.

---

## Uninstall

```sh
sh uninstall.sh
# or, for full cleanup:
sh uninstall.sh --remove-packages --remove-state --restore-crontab
```

Symbolic UCI restore from `snapshot.env` (does not clobber user edits made
after install). **extroot + swap are never touched.**

Fail-fast philosophy and full restore details: see
[README_RU.md](README_RU.md) §Отказы and §Удаление.

---

## License

MIT.
