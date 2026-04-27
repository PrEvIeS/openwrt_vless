# OpenWrt Mihomo Gateway — установщик

Транспарентный шлюз для OpenWrt 24.10.x / 25.04 / 25.12.x. Пакетный
менеджер (`opkg` на 24.10.x, `apk` на 25.x) детектится автоматически.
EN-вариант: [README.md](README.md).

Состав:

- **mihomo** (пакеты `nikki` + `luci-app-nikki`) — VLESS+Reality транспорт, fake-IP DNS, маршрутизация по правилам (geosite `ru-blocked` / `ru-available-only-inside` от [runetfreedom](https://github.com/runetfreedom/russia-v2ray-rules-dat)).
- **zapret** (дистрибутив remittor) — DPI-обход для YouTube/SmartTV без VPN, прямая маршрутизация.
- **AdGuard Home** — фильтрация рекламы/трекеров/телеметрии для LAN, DoH-апстримы.
- **Force DNS** — firewall DNAT `lan:53 → LAN_IP:53`, перехват DNS у устройств с hardcoded-резолверами.

Итоговая маршрутизация:

Порядок правил mihomo (первое совпадение — выигрыш):

1. LAN / RFC1918 → **DIRECT**
2. YouTube domain-suffix (`youtube.com`, `googlevideo.com`, `ytimg.com`, `youtu.be`, `ggpht.com`, `yt3/yt4.ggpht.com`) → **YOUTUBE selector** (default `VLESS-REALITY`, fallback `DIRECT`+zapret)
3. `geosite:ru-available-only-inside` (`.yandex.net`, `kinopoisk-ru.clstorage.net`, `cdnvideo.ru`) → **DIRECT**
4. `.ru` / `.рф` / `.su` / `GEOIP,RU` → **DIRECT**
5. `geosite:ru-blocked` (антифильтр + re:filter) → **PROXY selector → VPS**
6. `MATCH` → **FINAL selector** (default VLESS, переключается в mihomo UI / API)

YouTube идёт через VLESS первым по умолчанию: SmartTV YT-app использует только TCP/443, который RU ISP DPI режет — без VLESS приложение виснет на TLS handshake. ПК-Chrome спасает QUIC fallback, поэтому десктоп можно держать на DIRECT через zapret.

---

## Требования

| Параметр | Значение |
|---|---|
| OpenWrt | релиз из `SUPPORTED_RELEASES` (по умолчанию: `24.10.0 24.10.1 24.10.2 25.04.0 25.12.0 25.12.1 25.12.2`). Расширение: `SUPPORTED_RELEASES="25.12.3" sh install.sh` |
| Архитектура | `mipsel_24kc`, `mips_24kc`, `aarch64_cortex-a53/-a72/-generic`, `arm_cortex-a7/-a7_neon-vfpv4/-a9/-a9_vfpv3-d16/-a15_neon-vfpv4`, `x86_64`, `i386_pentium4`, `i386_pentium-mmx`. Env-override: `SUPPORTED_ARCHES="..."` |
| Пакетник | `apk` (25.x) или `opkg` (24.10.x), детект автоматический |
| RAM | ≥ 200 MB (на 256 MB стек работает впритык) |
| extroot | `/overlay` на ext4-разделе USB/SD/NVMe, ≥ 2 GiB |
| swap | активный swap ≥ 1 GiB (рекомендуется 1.5 GiB) |
| VLESS | URL `vless://UUID@host:port?type=tcp&security=reality&pbk=...&sni=...&sid=...&flow=xtls-rprx-vision&fp=chrome#label` |
| Интернет | работающий WAN на роутере |
| Доступ | root SSH |

Несоответствия preflight'а → exit 2, без мутаций. `--force`-escape нет.
Фактические пакеты nikki/zapret скачивают сами по `DISTRIB_ARCH` и
пакетнику — installer только валидирует allowlist.

---

## Формат VLESS URL

```
vless://UUID@host:port?type=tcp&security=reality&pbk=PUBKEY&sni=SNI&sid=HEX&flow=xtls-rprx-vision&fp=chrome#label
```

| Поле | Обязательность | Валидация | Дефолт (если нет в URL) |
|---|---|---|---|
| `UUID` | обяз. | `[A-Za-z0-9-]` | — |
| `host` | обяз. | `[A-Za-z0-9.:_-]` | — |
| `port` | опц. | 1..65535 | 443 |
| `pbk` | обяз. | base64url `[A-Za-z0-9_-]` | — |
| `sid` | обяз. | hex | — |
| `sni` | опц. | домен | `www.google.com` |
| `flow` | опц. | `[A-Za-z0-9._-]` | `xtls-rprx-vision` |
| `fp` | опц. | `[A-Za-z0-9._-]` | `chrome` |
| `type` | опц. | tcp (другое — warn) | `tcp` |
| `security` | опц. | только `reality` | `reality` |
| `#fragment` | — | игнорируется | — |

Приоритет источников: `--vless-*` override > значение из URL > fallback-default.

---

## Подготовка (до запуска установщика)

Установщик не выполняет прошивку и не настраивает extroot — только ставит
слой сервисов поверх уже готовой среды.

### 1. Прошить OpenWrt

1. На <https://firmware-selector.openwrt.org/> выбрать модель, скачать **factory**-образ.
2. Прошить через стоковый web-интерфейс (System Tools → Upgrade).
3. После ребута открыть LuCI на `192.168.1.1`, задать root-пароль.
4. Проверить: `cat /etc/openwrt_release` → `DISTRIB_RELEASE` из `SUPPORTED_RELEASES`, `DISTRIB_ARCH` из `SUPPORTED_ARCHES`.
5. Настроить WAN и Wi-Fi.

### 2. Настроить extroot + swap

1. Разметить флешку на две партиции:
   - `/dev/sda1` — Linux swap, ≥ 1.5 GiB
   - `/dev/sda2` — ext4, остальное пространство
2. Подключить в USB-порт роутера, зайти по SSH.
3. Поставить драйверы:
   ```sh
   apk update
   apk add block-mount e2fsprogs kmod-fs-ext4 kmod-usb-storage kmod-usb-storage-uas kmod-usb3
   block info   # должен показать sda1 (swap) и sda2 (ext4)
   ```
4. В LuCI → System → Mount Points:
   - `/dev/sda2` → Enabled, Target = **Use as external overlay (/overlay)**
   - `/dev/sda1` → Swap Enabled
   - Save & Apply → `reboot`
5. После ребута проверить:
   ```sh
   df -h      # /overlay на sda2
   free -m    # Swap активен
   ```

Без этого preflight отдаст `refuse` с exit 2.

---

## Установка

### Интерактивно

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/PrEvIeS/openwrt_vless/main/install.sh
sh /tmp/install.sh
```

Запрашивается только VLESS URL — парсер сам извлекает поля.

### Non-interactive

```sh
sh install.sh --non-interactive \
    --vless-url 'vless://UUID@your-vps.example.com:443?type=tcp&security=reality&pbk=PUBKEY&sni=www.google.com&sid=SHORT_ID&flow=xtls-rprx-vision&fp=chrome#label'
```

Кавычки обязательны (`&` и `?` — метасимволы шелла). `#fragment` в URL
игнорируется.

### Override отдельных полей

```sh
sh install.sh \
    --vless-url 'vless://.../' \
    --vless-sni my.cdn.example.com   # перезапишет sni из URL
```

### CLI-флаги

| Флаг | Назначение |
|---|---|
| `--vless-url URL` | Основной вход. Без флага — промпт (кроме `--non-interactive`). |
| `--vless-server/port/uuid/pubkey/sid/sni/flow/fp` | Override отдельных полей VLESS. |
| `--nfqws-opt "..."` | Строка NFQWS_OPT. Дефолт — `DEFAULT_NFQWS_OPT` в `install.sh`. |
| `--no-zapret` | Не устанавливать zapret. |
| `--no-adguard` | Не устанавливать AdGuard Home. |
| `--no-force-dns` | Не добавлять firewall-правило Force DNS. |
| `--no-i18n` | Не ставить `luci-i18n-nikki-ru`, `luci-i18n-statistics-ru`, `luci-i18n-sqm-ru`. |
| `--force-config` | Перезаписать `AdGuardHome.yaml`, nikki-профиль, snapshot. **Сбрасывает `bind_port: 3000` в AGH** — если после первой установки admin был перенесён на `:8080` через wizard, после `--force-config` wizard снова поднимется на `:3000`. |
| `--non-interactive` | Не промптить; без `--vless-url` или override'ов — die. |
| `-h`, `--help` | Справка. |
| env `SUPPORTED_RELEASES` / `SUPPORTED_ARCHES` | Расширить allowlist'ы. |

`--no-adguard` требует явного `--no-force-dns`. Force DNS — DNAT `lan:53 → LAN_IP:53`; без AGH на `LAN_IP:53` никто не слушает (dnsmasq на `:54`, mihomo на `:1053`), DNS у клиентов сломается. Preflight отдаёт `refuse` (exit 2) при такой комбинации.

---

## Что делает установщик (16 шагов)

Идемпотентность: `/etc/openwrt-setup-state` маркирует завершённые шаги; повторный запуск пропускает done-шаги, кроме `--force-config` (полный пересев).

0. **First-time setup** — root passwd / SSH authorized_keys / TZ если ещё не заданы.
1. **Preflight release + arch + pkg-manager** — `DISTRIB_RELEASE` ∈ `SUPPORTED_RELEASES`, `DISTRIB_ARCH` ∈ `SUPPORTED_ARCHES`, детект `apk` (25.x) либо `opkg` (24.10.x).
2. **Preflight extroot + swap** — `/overlay` на USB/SD/NVMe ≥ 2 GiB + активный swap ≥ 1 GiB.
3. **Preflight conflicts** — нет xray/sing-box/passwall/podkop; LAN = `br-lan`; `:53` у dnsmasq либо свободен; WAN работает.
4. **Сбор и разбор VLESS URL** — парсинг в поля, валидация каждого по строгому allowlist'у (защита от YAML-injection в профиль mihomo).
5. **Snapshot state** — `snapshot.env` (UCI-значения для symbolic restore) + копии `/etc/config/{network,dhcp,firewall}` + nftables ruleset + crontab, всё в `/root/openwrt-mihomo-backup/` (`chmod 700`).
6. **Установка базовых пакетов** — `curl ca-bundle block-mount e2fsprogs kmod-fs-ext4 kmod-usb-storage kmod-usb-storage-uas kmod-usb3`.
7. **nikki (mihomo)** — скачивание `feed.sh` от `nikkinikki-org/OpenWrt-nikki`. Если feed заблокирован DPI (`*.pages.dev` SNI-блок у RU ISP) — fallback на GitHub-релизы tarball'ом. Установка `nikki`, `luci-app-nikki`, опц. `luci-i18n-nikki-ru`.
8. **zapret** — запуск `update-pkg.sh` от `remittor/zapret-openwrt`, установка `zapret` и `luci-app-zapret`.
9. **AdGuard Home** — `apk add adguardhome`, конфиг = `/etc/adguardhome/adguardhome.yaml`.
10. **luci-theme-argon** — тема LuCI.
11. **luci-app-statistics + collectd** — графики (`luci-i18n-statistics-ru` опц.).
12. **SQM cake** — `luci-app-sqm` + `kmod-sched-cake` (`luci-i18n-sqm-ru` опц.). Bandwidth = `0/0` (юзер задаёт сам в LuCI → SQM QoS).
13. **Конфигурация (Step 14/16)**:
    - `/etc/nikki/profiles/main.yaml` (`chmod 600`) — VLESS-параметры, fake-IP DNS на `:1053`, правила DIRECT/YOUTUBE/`ru-available-only-inside`/`ru-blocked`/FINAL.
    - UCI `nikki.config`: `enabled=1`, `mode=redir_tun`.
    - UCI `nikki.mixin.*` — override поверх YAML каждый старт (`mixin.uc`): `dns_listen=127.0.0.1:1053`, `api_listen=127.0.0.1:9090`, `tproxy_port=7891`, `redir_port=7892`, `outbound_interface=wan`, `api_secret=132019`, `ipv6=0`. Без этого пакетные дефолты (`[::]:1053`) ломают UDP DNS к AGH.
    - `/etc/hotplug.d/net/30-nikki-fakeip` — `ip route replace 198.18.0.0/16 dev nikki` при `INTERFACE=nikki ACTION=add`.
    - geosite/geoip pre-download (`curl --resolve` поверх ещё-не-резолвящего DNS) → `/etc/nikki/run/{geosite,geoip}.dat` от runetfreedom.
    - UCI `zapret.config`: ВСЕ ключи UPPERCASE (remittor читает `NFQWS_OPT` / `MODE_FILTER`, не `nfqws_opt`); `MODE=nfqws`, `MODE_FILTER=hostlist`, `NFQWS_TCP_PORT=80,443`, `NFQWS_UDP_PORT=443`, `DISABLE_IPV6=1`, `NFQWS_OPT=<строка из 7 секций через --new>`. UCI `set` режет значение на первом `\n`, поэтому `NFQWS_OPT` собирается single-line через инкрементальный concat. После UCI обязательно `/opt/zapret/sync_config.sh` — иначе runtime читает старые `/opt/zapret/config`.
    - `/opt/zapret/ipset/zapret-hosts-user.txt` — 16+ YouTube/Google-CDN доменов.
    - dnsmasq → `:54`, `cachesize=0`, `noresolv=1`, `expandhosts=1`. DHCP: `option 3,$LAN_IP`, `option 6,$LAN_IP`, `option 15,lan`.
    - `/etc/adguardhome/adguardhome.yaml` — пре-сид: upstreams `[/lan/]127.0.0.1:54`, `[/pool.ntp.org/]1.1.1.1/1.0.0.1`, `127.0.0.1:1053`; bootstrap `1.1.1.1 8.8.8.8`; фильтры AdGuard DNS / AdGuard Russian / HaGeZi Encrypted DNS-VPN-Proxy-Bypass; retention 24h/720h; `users: []` (пароль задаётся через wizard).
    - Firewall redirect `Force DNS`: `lan:53 → $LAN_IP:53 (tcpudp)`.
14. **Порядок служб** — rc.d: `S50nikki → S60adguardhome → S99zapret`. nikki раньше AGH (AGH-upstream `127.0.0.1:1053` должен слушать к первому запросу), zapret — последним.
15. **Enable + start** всех трёх служб.
16. **Self-test + summary** — `pidof` каждого демона, проверка сокетов `:53 :54 :1053 :9090`, наличие firewall-правила, печать summary. FAIL → exit 1, state остаётся, откат через `uninstall.sh`.

---

## Файлы и места изменений

| Путь | Что содержит | В snapshot? | Восстанавливается `uninstall.sh`? |
|---|---|---|---|
| `/etc/config/dhcp` | dnsmasq-порт, DHCP-option'ы, upstream'ы | да (UCI symbolic) | да |
| `/etc/config/firewall` | redirect `Force DNS` | да (файл копируется) | правило `Force DNS` удаляется |
| `/etc/config/nikki` | `enabled`, `profile`, `mode` | нет | `enabled=0` |
| `/etc/config/zapret` | `mode`, `nfqws_opt`, порты | нет | `enabled=0` |
| `/etc/config/adguardhome` | `workdir` | нет | `enabled=0` |
| `/etc/config/network` | копия для отката | да (файл копируется) | не перезаписывается автоматически |
| `/etc/hosts` | копия для отката | да | не перезаписывается автоматически |
| `/etc/nikki/profiles/main.yaml` | VLESS-профиль (chmod 600) | нет | с `--remove-state` |
| `/etc/nikki/run/{geosite,geoip}.dat` | runetfreedom rules-data | нет | с `--remove-state` |
| `/etc/hotplug.d/net/30-nikki-fakeip` | hot-add 198.18/16 → dev nikki | нет | удаляется |
| `/etc/adguardhome/adguardhome.yaml` | конфиг AGH | нет | с `--remove-state` |
| `/opt/zapret/ipset/zapret-hosts-user.txt` | YouTube/Google-CDN домены | нет | с `--remove-state` |
| `/etc/openwrt-setup-state` | step-state идемпотентности | нет | удаляется |
| `/etc/rc.d/S{50nikki,60adguardhome,99zapret}` | порядок автозапуска | нет | удаляются (stop+disable) |
| `/root/openwrt-mihomo-backup/` | snapshot + копии конфигов + nftables + crontab | — | не удаляется |

---

## Порты и сервисы

| Порт | Слушает | Назначение |
|---|---|---|
| `:53/tcpudp` | AdGuard Home | DNS для LAN, upstream → mihomo :1053 или dnsmasq :54 |
| `:54/tcpudp` | dnsmasq | Только `.lan`, cache=0, noresolv=1 |
| `:1053/tcpudp` | mihomo | fake-IP DNS для правил mihomo |
| `:3000/tcp` | AdGuard Home | Admin wizard (до первого логина) |
| `:8080/tcp` | AdGuard Home | Admin (после переноса в wizard'е) |
| `:9090/tcp` | mihomo | external-controller (используется LuCI → Nikki) |
| `:7890/tcp` | mihomo | mixed-port (SOCKS/HTTP) |
| `:7891/tcp` | mihomo | tproxy-port |
| `:7892/tcp` | mihomo | redir-port |
| `:80/tcp` | uhttpd (LuCI) | Управление роутером |

---

## Пост-установка

### AGH wizard (обязательно — пароль)

Открыть `http://LAN_IP:3000`:

- Admin Web Interface: LAN_IP, port **8080**.
- DNS Server: All interfaces, port **53**.
- Логин/пароль — задать вручную (bcrypt-генерация в BusyBox отсутствует, автосеять нельзя).

Проверить `Settings → DNS Settings`: upstreams уже пре-сидированы, порядок:

```
[/lan/]127.0.0.1:54
[/pool.ntp.org/]1.1.1.1
[/pool.ntp.org/]1.0.0.1
127.0.0.1:1053
```

### blockcheck для zapret

Дефолтная NFQWS-стратегия — 7 секций через `--new`, проверена на TR3000 + RU ISP:

1. **TCP/443 google-hostlist** `fake` + `tls-fake-clienthello` (ggpht.com SNI), `repeats=8`, `fooling=badseq`.
2. **TCP/443 google-hostlist** `multisplit pos=2,sld` + `seqovl=620` + `tls-pattern`.
3. **TCP/443 user-hostlist** `hostfakesplit host=mapgl.2gis.com`.
4. **TCP/80** `multisplit` + `badsum`.
5. **UDP/443 user-hostlist** `fake` QUIC-clienthello `quic_initial_www_google_com.bin`, `repeats=6`.
6. **UDP discord/stun** `l7=discord,stun fake`.
7. **TCP CF-alt 2053-8443** `discord.media multisplit seqovl=652`.

Особенности procd-argv: combined-mode (`fake,multisplit` или `badsum,badseq`) parser режет на запятой → каждая секция использует один mode, комбинации разнесены через `--new`.

У части провайдеров нужна другая стратегия:

```sh
service zapret stop
/opt/zapret/blockcheck.sh
```

Параметры: `https + quic`, level=`standard`, curl-mode=`curl`,
target=`youtube.com`. По результатам скопировать лучшую стратегию в
LuCI → Services → Zapret → Settings → `NFQWS_OPT`.

---

## Проверка работы

```sh
# на роутере
ping 1.1.1.1
free -m                             # swap активен
df -h                               # /overlay на USB

# с клиента LAN
nslookup youtube.com LAN_IP         # fake-IP 198.18.x.x — mihomo отработал
nslookup yandex.ru LAN_IP           # реальный IP (yandex DoH)
nslookup doubleclick.net LAN_IP     # 0.0.0.0 — AGH заблокировал

# с клиента (браузер)
https://ifconfig.me                 # IP VPS — VLESS работает
https://yandex.ru/internet          # домашний IP — RU напрямую
https://www.youtube.com             # открывается, без деградации
```

---

## Архитектура

```
[клиенты LAN, включая Smart TV]
    │  (Wi-Fi / Ethernet)
    ▼
┌─────────────────────────────────────────┐
│  OpenWrt                                │
├─────────────────────────────────────────┤
│  DNS:                                   │
│  ├─ firewall DNAT :53  (принудительно)  │
│  ├─ AGH        :53     (фильтр + лог)   │
│  ├─ mihomo     :1053   (fake-IP + rules)│
│  └─ dnsmasq    :54     (только .lan)    │
│                                         │
│  Трафик:                                │
│  ├─ mihomo TProxy → DIRECT или VPS      │
│  ├─ VLESS-Reality → VPS (blocked)       │
│  └─ zapret nfqws  → DPI-обход YouTube   │
│                                         │
│  Управление:                            │
│  ├─ LuCI        :80                     │
│  ├─ AGH UI      :8080                   │
│  └─ mihomo UI   через LuCI → Nikki      │
└─────────────────────────────────────────┘
    │
    ▼
[WAN → провайдер]
    ├── напрямую: RU-трафик + YouTube (zapret)
    └── через VPS: заблокированные в РФ
```

---

## IPv6 — текущее поведение

Установщик настраивает **только IPv4-маршрутизацию**. Что это значит на практике:

- **mihomo fake-IP** подменяет только A-записи. AAAA проходит «как есть», поэтому v6-пункты назначения не попадают под правила geosite / YouTube / geoip и идут мимо mihomo.
- **zapret** зафиксирован с `disable_ipv6=1` в UCI — nfqws-хук смотрит только IPv4.
- **Force-DNS redirect** — только v4 (`ip nat` DNAT, без ip6nat-аналога).

Итоговый эффект: если у LAN-клиента работает IPv6 на заблокированный ресурс, браузер по Happy Eyeballs предпочтёт v6 и **обойдёт VLESS целиком**. Рекомендация — отключить IPv6 на LAN-интерфейсе:

- LuCI → Network → Interfaces → LAN → Advanced Settings: `IPv6 assignment length` = *disabled*.
- LuCI → Network → Interfaces → LAN → DHCP Server → IPv6 Settings: `RA-Service` = *disabled*, `DHCPv6-Service` = *disabled*.

Альтернативно на уровне ядра (жёстче, отключает v6 целиком):

```sh
echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf
sysctl -p
```

Полноценный флаг `--ipv6 {bypass,drop,route}` с тремя политиками (пропустить v6 мимо — текущее поведение, блокировать v6 на firewall, пытаться маршрутизировать через mihomo когда появится v6 fake-IP) — в плане на [ROADMAP.md](ROADMAP.md).

---

## Типовые проблемы

| Симптом | Диагностика / решение |
|---|---|
| DNS не резолвит ничего | `logread \| grep -E 'AdGuard\|nikki'`. `:53` слушается? `ss -lntu \| grep ':53'`. Force DNS на месте? `uci show firewall \| grep "Force DNS"` |
| mihomo не стартует после ребута | `logread \| grep nikki`. Обычно YAML-ошибка в `/etc/nikki/profiles/main.yaml` → править в LuCI → Nikki → Profile Editor |
| YouTube работает в браузере, не на SmartTV | DNS-interception включён? QUIC в `NFQWS_OPT`? IPv6 отключён на LAN? `cat /sys/module/ipv6/parameters/disable` |
| Госуслуги/банки не работают через zapret | `mode_filter=hostlist` обязателен — zapret режет TLS только хостам из `zapret-hosts-user.txt`. Проверить `uci get zapret.config.mode_filter` |
| Конфликт на :53 | `ss -lntp \| grep ':53'`. Ожидается только AdGuardHome. Если dnsmasq — migrate_dnsmasq_to_agh не отработала, проверить `uci get dhcp.@dnsmasq[0].port` = 54 |
| RAM ≥ 90% | Отключить лишние блоклисты AGH, уменьшить retention querylog, `--no-i18n` при переустановке. На 256 MB держать 3–4 блоклиста максимум |
| VLESS медленный | CPU-потолок слабых SoC (MT7621 и аналоги) — 70–80 Мбит/с через VLESS-Reality. Решение — роутер помощнее (aarch64 / x86_64) |

---

## Режимы сбоев (fail-fast)

| Exit | Когда | Что делать |
|---|---|---|
| 0 | self-test пройден | — |
| 2 | preflight отказ (release / arch / pkg / extroot / conflicts / VLESS URL) | исправить среду по сообщению, перезапустить |
| 1 | ошибка после начала мутаций (snapshot создан) | `sh uninstall.sh`, разобраться |

Никакого auto-rollback и retry. Откат — только через `uninstall.sh`.

---

## Удаление

```sh
sh uninstall.sh                                                  # stop + UCI restore
sh uninstall.sh --remove-packages --remove-state --purge-config  # полная очистка
sh uninstall.sh --restore-crontab                                # crontab из snapshot
```

| Действие | Default | С флагом |
|---|---|---|
| Stop + disable `nikki / adguardhome / zapret`, снятие rc.d-симлинков | да | — |
| Удаление firewall-правила `Force DNS` | да | — |
| Symbolic UCI restore из `snapshot.env` (dnsmasq :54→:53, DHCP options, lan.dns) | да | — |
| UCI секции `/etc/config/{nikki,zapret,adguardhome}` | `enabled=0` | `--purge-config` → `rm` |
| Удаление пакетов `nikki / zapret / adguardhome` | нет | `--remove-packages` |
| Удаление `/etc/nikki`, `/opt/adguardhome`, `/opt/zapret` | нет | `--remove-state` |
| crontab | не трогается | `--restore-crontab` → из snapshot |
| extroot, swap, прошивка | не трогаются | — |

UCI восстанавливается **символьно** — файлы конфигурации не перезаписываются, правки пользователя после установки сохраняются. `install.sh` свой crontab не модифицирует, поэтому default — cron не трогать.

Прошивка не откатывается — для возврата на сток использовать U-Boot web recovery роутера, если поддерживается.

---

## Лицензия

Скрипты — MIT. Сторонние пакеты — по своим лицензиям (mihomo / nikki /
zapret / AdGuard Home).
