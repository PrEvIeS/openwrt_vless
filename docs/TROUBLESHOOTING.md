# Troubleshooting

Типовые сбои и их разбор. Формат: **симптом → причина → что делать**.

Если не нашёл свой случай — открывай issue через шаблон
`.github/ISSUE_TEMPLATE/bug_report.md`, прикладывай вывод команд из секции
"Диагностика" ниже.

---

## Preflight refuse (exit 2)

### "unsupported OpenWrt release: X"

**Причина:** `/etc/openwrt_release` сообщает релиз вне `SUPPORTED_RELEASES`.

**Что делать:**
```sh
cat /etc/openwrt_release | grep DISTRIB_RELEASE
# если релиз новый (например 25.12.3) и ты готов к риску:
SUPPORTED_RELEASES="25.12.3" sh install.sh
# если старый (23.x и раньше) — обновление прошивки обязательно, скрипт работать не будет
```

### "unsupported architecture: X"

**Причина:** `DISTRIB_ARCH` вне `SUPPORTED_ARCHES` (MIPS/aarch64/arm/x86).

**Что делать:** проверить, есть ли mihomo-бинарь под эту архитектуру в
релизах upstream. Если есть — расширить `SUPPORTED_ARCHES` через env:
```sh
SUPPORTED_ARCHES="your_arch_here" sh install.sh
```
Если нет — apk/opkg упадёт на шаге 7, поддержка невозможна.

### "extroot not mounted on /overlay"

**Причина:** `/overlay` — это внутренний squashfs/tmpfs роутера, места для
пакетов не хватит.

**Что делать:** настроить extroot до запуска install.sh. Инструкция в
`README_RU.md §Подготовка → Extroot`. Кратко:
```sh
# USB/SD, ext4, UUID
block detect | uci import fstab
uci set fstab.@mount[-1].target='/overlay'
uci set fstab.@mount[-1].enabled='1'
uci commit fstab
reboot
```
Проверка после ребута: `df -h /overlay` должен показать диск, не tmpfs.

### "swap not active" / "swap < 1 GiB"

**Причина:** шаги 7-9 (установка пакетов) требуют RAM, без swap OOM-killer
убьёт процесс.

**Что делать:**
```sh
# создать 1.5 GiB swap на extroot
dd if=/dev/zero of=/overlay/swap.img bs=1M count=1536
chmod 600 /overlay/swap.img
mkswap /overlay/swap.img
swapon /overlay/swap.img

# сделать постоянным
uci add fstab swap
uci set fstab.@swap[-1].device='/overlay/swap.img'
uci set fstab.@swap[-1].enabled='1'
uci commit fstab
```

### "rival proxy detected: X" (xray / sing-box / passwall / podkop / mihomo)

**Причина:** другой прокси-стек установлен и работает — конфликт по
портам/tun-интерфейсу/firewall.

**Что делать:** снести его **штатным средством**, не `opkg remove` вручную.
Для passwall/openclash/podkop — через LuCI → Services → Uninstall.
Проверка чистоты:
```sh
pgrep -f 'xray|sing-box|mihomo|clash|v2ray' && echo "STILL RUNNING"
ls /etc/config/{xray,passwall,openclash,podkop} 2>/dev/null
```

### ":53 occupied by X (not dnsmasq)"

**Причина:** AGH, unbound, pihole или что-то ещё уже слушает `:53`.

**Что делать:** либо удалить этого резолвера (если не нужен), либо
перенести его на другой порт до запуска install.sh. Установщик не будет
бороться за `:53` сам — это fail-fast by design.

### "VLESS URL parse error: missing field X"

**Причина:** URL повреждён — нет `pbk`, `sni`, `sid`, или неправильный
`security=reality`/`type=tcp`.

**Что делать:**
- Скопировать URL из клиента без переносов строк.
- Если поле реально отсутствует — указать через флаг:
  ```sh
  sh install.sh --vless-url '...' --vless-pbk 'KEY' --vless-sni 'www.google.com'
  ```
- Приоритет: `--vless-*` флаг > URL-поле.

---

## После снапшота (exit 1)

### "package installation failed: X"

**Причина:** apk/opkg не смог дотянуться до фида (DNS/WAN проблема,
упавший upstream, разошедшийся индекс пакетов).

**Что делать:**
```sh
# обновить индекс вручную
opkg update   # OpenWrt 24.10.x
apk update    # OpenWrt 25.x

# проверить WAN
ping -c 3 1.1.1.1
ping -c 3 downloads.openwrt.org

# если nikki feed — проверить отдельно
ls /etc/opkg/customfeeds.conf /etc/apk/repositories.d/ 2>/dev/null

# откат
sh uninstall.sh
```
После фикса запустить install.sh заново с теми же флагами.

### "nikki feed signature invalid"

**Причина:** GPG-ключ nikki feed изменился, локальный keyring устарел.

**Что делать:** см. upstream README
[nikkinikki-org/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki).
Обновить ключ, затем перезапустить.

---

## Self-test FAIL (шаг 12, exit 1)

### "port :53 not bound by AdGuardHome"

**Причина:** AGH не стартанул (OOM, битый конфиг, porclash с dnsmasq).

**Диагностика:**
```sh
logread -e AdGuardHome
netstat -lnup | grep :53
cat /etc/AdGuardHome.yaml | head -20
```
**Что делать:** `service adguardhome restart` — если не помогает, смотри
следующий пункт.

### "mihomo process not running"

**Причина:** битый VLESS URL (UUID/pubkey принимаются, но сервер
отвергает), tun недоступен, недостаточно памяти.

**Диагностика:**
```sh
logread -e nikki
logread -e mihomo
ls /dev/net/tun
free -m   # MemAvailable должен быть > 50 MB
cat /etc/nikki/profiles/default.yaml | head -30
```
**Что делать:**
- Проверить VLESS URL в клиенте для ПК — если не соединяется там, проблема
  на стороне сервера.
- Проверить, что tun-kmod установлен: `lsmod | grep tun`.
- При нехватке памяти — увеличить swap.

### "firewall rule missing: Force-DNS redirect"

**Причина:** UCI commit не прошёл, или `/etc/config/firewall` перезаписан
сторонним скриптом.

**Диагностика:**
```sh
uci show firewall | grep -i mihomo-gateway
nft list ruleset | grep -A5 'dnat.*53'
```
**Что делать:** `fw4 reload` — если ничего не появилось, значит шаг 10
провалился тихо. Запустить `sh uninstall.sh` и повторить install.sh.

---

## После install (работает, но…)

### YouTube тормозит / не играет выше 480p

**Причина:** NFQWS_OPT по умолчанию — starting set, для конкретного ISP
может не подойти.

**Что делать:**
```sh
service zapret stop
/opt/zapret/blockcheck.sh
# → выбрать YouTube, выбрать рекомендованный набор опций
# → открыть LuCI → Services → Zapret → NFQWS_OPT → вставить
# → сохранить, service zapret start
```

### YouTube не работает на Smart TV (Yandex Station / Tizen / WebOS / Android TV)

**Симптом:** на ПК через тот же роутер YouTube открывается, на Smart TV
YT-app виснет на splash или вечный буфер. `mihomo /connections` показывает
соединения от TV к `www.youtube.com:443` с `upload>0`, но `download=0`.

**Причина:** mihomo `proxy-groups → YOUTUBE` selector выбирает `DIRECT`.
RU ISP DPI обрывает TCP/443 к youtube.com на TLS handshake. Chrome на ПК
работает потому что использует QUIC (UDP/443) — другой механизм блокировки.
Smart TV YT-app — TCP-only без QUIC fallback, виснет.

**Что делать:**

Через mihomo HTTP API (без рестарта):
```sh
SECRET=$(uci get nikki.mixin.api_secret)
curl -X PUT -H "Authorization: Bearer $SECRET" \
     -H "Content-Type: application/json" \
     -d '{"name":"VLESS-REALITY"}' \
     http://127.0.0.1:9090/proxies/YOUTUBE
# дропнуть зависшие соединения
curl -X DELETE -H "Authorization: Bearer $SECRET" \
     http://127.0.0.1:9090/connections
```

Через профиль (persistent):
```sh
sed -i '/name: "YOUTUBE"/,/proxies:/ s/\[DIRECT, VLESS-REALITY\]/[VLESS-REALITY, DIRECT]/' \
    /etc/nikki/profiles/main.yaml
/etc/init.d/nikki restart
```

Свежие установки install.sh с 0.2.1+ имеют правильный default —
`proxies: [VLESS-REALITY, DIRECT]`. Через UI mihomo (`http://router-ip:9090/ui/`)
можно вручную тогглить YOUTUBE между VLESS и DIRECT, выбор сохраняется
в `/etc/nikki/cache/cache.db` через рестарты.

**Диагностика:**
```sh
SECRET=$(uci get nikki.mixin.api_secret)
# Текущий selector группы
curl -s -H "Authorization: Bearer $SECRET" \
     http://127.0.0.1:9090/proxies/YOUTUBE | grep -oE '"now":"[^"]*"'
# Соединения от конкретного клиента (подставь IP TV)
curl -s -H "Authorization: Bearer $SECRET" \
     http://127.0.0.1:9090/connections | tr ',' '\n' \
   | grep -E '192\.168\.1\.<IP>|chains|host"|download'
```
Если `chains` содержит DIRECT и `download:0` — селектор группы и есть
причина.

### AGH wizard не открывается на `:3000`

**Причина:** порт занят, или bind только на LAN/loopback.

**Что делать:**
```sh
netstat -lnt | grep :3000
# если пусто — AGH не слушает, logread -e AdGuardHome
# если слушает 127.0.0.1:3000 — подключаться только с роутера:
ssh -L 3000:localhost:3000 root@<router_ip>
# потом в браузере http://localhost:3000
```
После первого захода wizard позволяет сменить bind на `0.0.0.0:8080`.

### Клиенты с хардкод-DNS (`1.1.1.1:443` DoH) обходят AGH

**Причина:** Force-DNS редиректит только `udp/tcp :53`. DoH/DoT в обход.

**Что делать:** известное ограничение, сейчас штатно не решается. Ручной
firewall-блок по IP вендорных DNS-резолверов — см. issue-трекер, это
в планах (см. `ROADMAP.md §Known limitations`).

### mihomo соединяется, но сайты не открываются

**Причина:** fake-IP работает только для v4. Клиент пытается идти по IPv6
напрямую в обход mihomo.

**Что делать (временный workaround):**
```sh
# отключить IPv6 на LAN
uci set network.lan.ipv6=off
uci set dhcp.lan.dhcpv6=disabled
uci commit
reboot
```
Постоянный фикс — в ROADMAP (`--ipv6 {bypass,drop,route}` флаг).

---

## Восстановление

### `uninstall.sh` прошёл, но роутер в странном состоянии

**Диагностика:**
```sh
ls /root/openwrt-mihomo-backup/
cat /root/openwrt-mihomo-backup/snapshot.env
# сравнить с текущим UCI
uci show dhcp.@dnsmasq[0].port   # должно быть 53 (снова), не 54
```

**Что делать:** `uninstall.sh --purge-config` дожимает оставшиеся UCI.
Если и после этого хвост — ручной `uci delete` по секциям из snapshot.env.
Крайний случай — factory reset и чистый flash.

### Snapshot директория удалена, а install упал

**Причина:** кто-то очистил `/root/openwrt-mihomo-backup/` до отката.

**Что делать:** `uninstall.sh` частично сработает (пакеты снимет), но UCI
симметрично не восстановит — будут остаточные `enabled=0` секции. Это не
ломает роутер, но захламляет конфиг.

---

## Диагностика (что прикладывать к issue)

```sh
# всегда
cat /etc/openwrt_release
uname -a
free -m
df -h

# pipeline state
ls /root/openwrt-mihomo-backup/ 2>/dev/null
service nikki status
service adguardhome status
service zapret status

# сетевой стек
netstat -lnupt | grep -E ':53|:1053|:3000|:7890|:9090'
nft list ruleset | grep -A3 'dnat.*53'
uci show firewall | grep -i mihomo
uci show dhcp.@dnsmasq[0]
ls /etc/AdGuardHome.yaml /etc/nikki/profiles/default.yaml

# логи
logread -e nikki | tail -50
logread -e AdGuardHome | tail -50
logread -e zapret | tail -50

# VLESS (BEFORE POSTING — вычисти UUID и pubkey!)
cat /etc/nikki/profiles/default.yaml | sed 's/\(uuid:\).*/\1 <redacted>/' | sed 's/\(public-key:\).*/\1 <redacted>/'
```
