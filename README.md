# OpenWrt Mihomo Gateway Installer

Three-layer transparent gateway for **OpenWrt 24.10.x / 25.04 / 25.12.x**.
Package manager is detected automatically (`opkg` on 24.10.x, `apk` on 25.x).

- **mihomo** via [`nikki`](https://github.com/nikkinikki-org/OpenWrt-nikki) — VLESS+Reality transport, fake-IP DNS, rule-based routing
- **zapret** via [`remittor`](https://github.com/remittor/zapret-openwrt) — DPI bypass for YouTube / SmartTV, no VPN tunneling
- **AdGuard Home** — LAN-wide ad/tracker/telemetry filter with DoH upstreams
- **Force-DNS firewall redirect** — intercepts hard-coded `:53` from clients

Primary documentation is Russian: [README_RU.md](README_RU.md). This page is a short orientation.

---

## Requirements

- OpenWrt release in `SUPPORTED_RELEASES` (default: `24.10.0 24.10.1 24.10.2 25.04.0 25.12.0 25.12.1 25.12.2`). Extend via env: `SUPPORTED_RELEASES="25.12.3" sh install.sh`.
- `DISTRIB_ARCH` in `SUPPORTED_ARCHES` (MIPS / aarch64 / arm / x86_64 / i386 variants).
- `/overlay` on USB/SD/NVMe (ext4) ≥ 2 GiB — extroot must be set up before running the installer.
- Active swap ≥ 1 GiB (1.5 GiB recommended).
- ≥ 200 MB RAM, root SSH, working WAN.
- Clean OpenWrt: no `xray` / `sing-box` / `mihomo` / `passwall*` / `podkop` running; `:53` held by stock `dnsmasq` or free.
- VLESS+Reality URL: `vless://UUID@host:port?type=tcp&security=reality&pbk=...&fp=chrome&sni=...&sid=...&flow=xtls-rprx-vision#label`.

Extroot setup is covered in [README_RU.md §Подготовка](README_RU.md).

---

## Quick start

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/PrEvIeS/openwrt_vless/main/install.sh
sh /tmp/install.sh
```

Interactive mode prompts for the VLESS URL only. Non-interactive example:

```sh
sh install.sh --non-interactive \
    --vless-url 'vless://UUID@host:443?type=tcp&security=reality&pbk=KEY&sni=www.google.com&sid=DEADBEEF&flow=xtls-rprx-vision&fp=chrome#label'
```

Override priority: `--vless-*` CLI flag > URL value > fallback default.

---

## CLI flags

| Flag | Purpose |
|---|---|
| `--vless-url URL` | Full VLESS Reality URL (required unless every field is set via `--vless-*` overrides) |
| `--vless-server/port/uuid/pubkey/sid/sni/flow/fp` | Override individual fields |
| `--nfqws-opt STR` | Custom zapret NFQWS strategy (default is a starting set, see `DEFAULT_NFQWS_OPT` in `install.sh`) |
| `--no-zapret` / `--no-adguard` / `--no-force-dns` / `--no-i18n` | Skip a layer |
| `--force-config` | Overwrite existing `AdGuardHome.yaml`, nikki profile and snapshot. Note: re-seeds AGH `bind_port: 3000`, so a custom admin port set earlier via the AGH wizard is reverted. |
| `--non-interactive` | Fail instead of prompting |
| `-h`, `--help` | Show usage |

`--no-adguard` requires `--no-force-dns` — Force DNS redirects clients to `LAN_IP:53`, which is empty without AGH (dnsmasq is on `:54`, mihomo on `:1053`). Installer refuses at preflight if only `--no-adguard` is set.

---

## 12-step pipeline

1. Preflight — release + architecture + package manager
2. Preflight — extroot + swap
3. Preflight — conflict probes (rival proxies, `:53` owner, LAN iface, internet)
4. Collect and parse VLESS URL, validate fields
5. Pre-install state snapshot at `/root/openwrt-mihomo-backup/` (chmod 700)
6. Base packages (`curl`, `block-mount`, USB-storage kmods, …)
7. `nikki` feed + mihomo packages
8. `zapret` via `remittor/update-pkg.sh`
9. `adguardhome`
10. Configure profiles, move `dnsmasq` to `:54`, firewall redirect, service order
11. Enable + start services (nikki → adguardhome → zapret)
12. Self-test (ports, daemons, firewall rule)

---

## Failure modes

| Phase | Exit | Behavior |
|---|---|---|
| Preflight refuse (release / arch / pkg / extroot / conflicts / VLESS URL) | **2** | nothing written, fix environment and re-run |
| Error after snapshot (mutations begun) | **1** | installer prints `sh uninstall.sh` hint, no auto-rollback |
| Self-test FAIL | **1** | per-check report printed, state kept, run `uninstall.sh` to revert |

No `--force` flag, no retry loops, no auto-rollback.

---

## Post-install (manual)

1. Open the AdGuard Home wizard at `http://<LAN_IP>:3000` — set admin port to `:8080`, DNS bind to all interfaces `:53`, create a password.
2. If YouTube is slow or blocked, tune the zapret strategy:
   ```sh
   service zapret stop
   /opt/zapret/blockcheck.sh
   # → update NFQWS_OPT in LuCI → Services → Zapret
   ```

---

## Uninstall

```sh
sh uninstall.sh
# or, for full cleanup:
sh uninstall.sh --remove-packages --remove-state --purge-config --restore-crontab
```

UCI values are restored symbolically from `snapshot.env`. `--purge-config` additionally removes `/etc/config/{nikki,zapret,adguardhome}` (default keeps them with `enabled=0` for reinstall). extroot and swap are never touched.

---

## License

MIT. Third-party packages keep their upstream licenses (mihomo / nikki / zapret / AdGuard Home).
