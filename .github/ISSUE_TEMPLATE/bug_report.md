---
name: Bug report
about: Installer fails, self-test fails, or post-install state is broken
title: 'bug: '
labels: bug
---

## Summary

One sentence. Что именно сломано.

## Environment

- OpenWrt release (`cat /etc/openwrt_release`):
- Target / subtarget / arch (`DISTRIB_TARGET`, `DISTRIB_ARCH`):
- Device model:
- Installer commit SHA or tag (`git rev-parse HEAD`):
- Flags used (`sh install.sh ...`):

## Reproduction

1.
2.
3.

## Expected

## Actual

## Diagnostic output

Вывод команд из `docs/TROUBLESHOOTING.md §Диагностика`. **ВАЖНО:**
перед вставкой вычисти `uuid:` и `public-key:` из нигдехо конфига.

<details>
<summary>openwrt_release / uname</summary>

```
<paste>
```
</details>

<details>
<summary>service status (nikki / adguardhome / zapret)</summary>

```
<paste>
```
</details>

<details>
<summary>netstat / nft / uci firewall</summary>

```
<paste>
```
</details>

<details>
<summary>logread (relevant services, last 50 lines)</summary>

```
<paste>
```
</details>

## Snapshot state

- `/root/openwrt-mihomo-backup/` exists? (`ls -la`):
- Ran `uninstall.sh` before reporting? yes/no
- If yes — did it exit clean?

## Additional context

Скриншоты LuCI, wireshark pcap (если релевантно и не содержит ключей),
ссылки на upstream issues (mihomo/nikki/zapret/AGH) если уже копал.
