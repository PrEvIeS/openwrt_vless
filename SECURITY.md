# Security Policy

## Scope

This installer modifies firewall rules, DNS resolution, routing, and installs
upstream packages (mihomo, nikki, zapret, AdGuard Home) on an OpenWrt router.
The following surfaces are security-sensitive and in scope for reports:

- **Preflight bypass** — any input that causes `install.sh` to proceed past
  preflight refuse conditions (rival proxy present, `:53` occupied, unsupported
  release, malformed VLESS URL).
- **UCI / firewall injection** — crafted VLESS URL fields, CLI flags, or env
  vars that inject UCI values, nftables rules, or shell metacharacters into
  `/etc/config/*` or generated profile files.
- **Snapshot integrity** — tampering that causes `uninstall.sh` to restore an
  incorrect pre-install state or expose secrets (VLESS UUID, pubkey) beyond
  `/root/openwrt-mihomo-backup/` (chmod 700).
- **DNS / fake-IP leaks** — traffic paths that bypass AdGuard Home and mihomo
  fake-IP resolution despite the documented policy (excluding documented
  limitations: DoH/DoT clients with hardcoded IPs, IPv6 bypass — see
  `ROADMAP.md §Known limitations`).
- **Privilege escalation** — any path in `install.sh` / `uninstall.sh` that
  executes attacker-controlled code with root privileges outside the declared
  pipeline steps.
- **Third-party package pinning** — supply-chain risks from upstream feeds
  (nikki, remittor/zapret) if the installer accepts unverified content.

## Out of scope

- DoS against the router itself via external traffic (not a gateway design
  goal; mitigated upstream by ISP / LAN policy).
- Vulnerabilities in upstream packages (mihomo, nikki, zapret, AdGuard Home) —
  report to the respective projects. This installer does not ship patches.
- Local privileged user abusing root SSH — not a threat model for a single-
  admin home router.
- Limitations already documented in `ROADMAP.md §Known limitations` (DoH/DoT
  hardcoded-IP bypass, IPv6 bypass, extroot/swap preservation on uninstall).
- Physical access to the device.

## Reporting

**Do not open public GitHub issues for security bugs.**

Preferred: **GitHub Security Advisories** on the
[PrEvIeS/openwrt_vless](https://github.com/PrEvIeS/openwrt_vless/security/advisories)
repository — use "Report a vulnerability" to open a private advisory.

Fallback: open a minimal public issue titled `security: private contact
needed` without technical details; a maintainer will respond with a private
channel.

Include in the report:
- OpenWrt release, target/subtarget, architecture.
- Installer version (commit SHA or tag).
- Flags and environment used.
- Reproducer: minimal steps, VLESS URL fields sanitised if irrelevant.
- Observed vs expected behaviour.
- Proof of impact (logs, `nft list ruleset`, `uci export`, pcap if relevant).

## Response

- Acknowledgement: within 7 days.
- Triage: within 14 days.
- Fix timeline: depends on severity; critical issues get an out-of-band patch
  release, others are bundled into the next MINOR / PATCH tag.
- Disclosure: coordinated via the GitHub advisory; CVE requested if applicable.

## Hardening recommendations for operators

Not vulnerabilities, but good practice:

- Change AdGuard Home admin port from the default `3000` to a LAN-only bound
  address after first-run wizard.
- Rotate VLESS UUID and Reality keys periodically; treat `snapshot.env` as
  secret.
- Keep `uninstall.sh --purge-config` as the cleanup path for compromised
  installs rather than manual UCI editing.
- Do not publish `/root/openwrt-mihomo-backup/` or logs to public issue
  threads without redacting `VLESS_*` values and public keys.
- Run behind an ISP router with NAT; do not expose router-WAN services.
