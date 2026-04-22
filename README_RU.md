# OpenWrt Mihomo Gateway — установщик

Транспарентный шлюз для OpenWrt 24.10.x / 25.04 / 25.12.x. Пакетный
менеджер (`opkg` на 24.10.x, `apk` на 25.x) детектится автоматически.
EN-вариант: [README.md](README.md).

Состав:

- **mihomo** (пакеты `nikki` + `luci-app-nikki`) — VLESS+Reality транспорт, fake-IP DNS, маршрутизация по правилам (`ru-blocked.list` от runetfreedom).
- **zapret** (дистрибутив remittor) — DPI-обход для YouTube/SmartTV без VPN, прямая маршрутизация.
- **AdGuard Home** — фильтрация рекламы/трекеров/телеметрии для LAN, DoH-апстримы.
- **Force DNS** — firewall DNAT `lan:53 → LAN_IP:53`, перехват DNS у устройств с hardcoded-резолверами.

Итоговая маршрутизация:

- `*.ru` / `*.рф` / `*.su` / `GEOIP,RU` → **DIRECT**
- YouTube и его CDN → **DIRECT + zapret DPI-bypass**
- `ru-blocked.list` → **VLESS-Reality → VPS**
- Остальное → **FINAL** (по умолчанию VLESS, меняется в LuCI)

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
| `--no-i18n` | Не ставить `luci-i18n-nikki-ru`. |
| `--force-config` | Перезаписать `AdGuardHome.yaml`, nikki-профиль, snapshot. **Сбрасывает `bind_port: 3000` в AGH** — если после первой установки admin был перенесён на `:8080` через wizard, после `--force-config` wizard снова поднимется на `:3000`. |
| `--non-interactive` | Не промптить; без `--vless-url` или override'ов — die. |
| `-h`, `--help` | Справка. |
| env `SUPPORTED_RELEASES` / `SUPPORTED_ARCHES` | Расширить allowlist'ы. |

`--no-adguard` требует явного `--no-force-dns`. Force DNS — DNAT `lan:53 → LAN_IP:53`; без AGH на `LAN_IP:53` никто не слушает (dnsmasq на `:54`, mihomo на `:1053`), DNS у клиентов сломается. Preflight отдаёт `refuse` (exit 2) при такой комбинации.

---

## Что делает установщик (12 шагов)

1. **Preflight release + arch** — `DISTRIB_RELEASE` ∈ `SUPPORTED_RELEASES`, `DISTRIB_ARCH` ∈ `SUPPORTED_ARCHES`, детект пакетника.
2. **Preflight extroot** — `/overlay` на USB/SD/NVMe ≥ 2 GiB + активный swap ≥ 1 GiB.
3. **Preflight conflicts** — нет xray/sing-box/passwall/podkop; LAN = `br-lan`; `:53` у dnsmasq либо свободен; WAN работает.
4. **Сбор и разбор VLESS URL** — парсинг в поля, валидация каждого поля по строгому allowlist'у (защита от YAML-injection в профиль mihomo).
5. **Snapshot state** — `snapshot.env` (UCI-значения для symbolic restore) + копии `/etc/config/{network,dhcp,firewall}` + nftables ruleset + crontab, всё в `/root/openwrt-mihomo-backup/` с `chmod 700` (содержит старые значения DNS/DHCP, не должно быть readable от `nobody`).
6. **Установка базовых пакетов** — `curl ca-bundle block-mount e2fsprogs kmod-fs-ext4 kmod-usb-storage kmod-usb-storage-uas kmod-usb3`.
7. **nikki (mihomo)** — скачивание `feed.sh` от `nikkinikki-org/OpenWrt-nikki`, добавление репозитория, установка `nikki`, `luci-app-nikki`, при необходимости `luci-i18n-nikki-ru`.
8. **zapret** — запуск `update-pkg.sh` от `remittor/zapret-openwrt`, установка `zapret` и `luci-app-zapret`.
9. **AdGuard Home** — `apk add adguardhome`, workdir = `/opt/adguardhome`.
10. **Конфигурация**:
    - `/etc/nikki/run/profiles/main.yaml` — VLESS-параметры, fake-IP DNS на `:1053`, правила RU→DIRECT + YouTube→YOUTUBE + `ru-blocked.list`→PROXY.
    - UCI `nikki.config`: `enabled=1`, `mode=redir_tun`.
    - UCI `zapret.config`: `mode=nfqws`, `mode_filter=hostlist`, `nfqws_tcp_port=80,443`, `nfqws_udp_port=443`, `disable_ipv6=1`, `nfqws_opt=<стратегия>`.
    - `/opt/zapret/ipset/zapret-hosts-user.txt` — 10 YouTube-доменов.
    - dnsmasq → `:54`, `cachesize=0`, `noresolv=1`, `expandhosts=1`. DHCP: `option 3,$LAN_IP`, `option 6,$LAN_IP`, `option 15,lan`.
    - `/opt/adguardhome/AdGuardHome.yaml` — пре-сид: upstreams `[/lan/]127.0.0.1:54`, `[/pool.ntp.org/]1.1.1.1/1.0.0.1`, `127.0.0.1:1053`; bootstrap `1.1.1.1 8.8.8.8`; фильтры AdGuard DNS / AdGuard Russian / HaGeZi Encrypted DNS-VPN-Proxy-Bypass; retention 24h/720h; `users: []` (пароль задаётся через wizard, bcrypt в BusyBox отсутствует).
    - Firewall redirect `Force DNS`: `lan:53 → $LAN_IP:53 (tcpudp)`.
11. **Порядок служб + enable + start** — `S50nikki → S60adguardhome → S99zapret`. nikki раньше AGH, чтобы AGH `:53 → mihomo :1053` был доступен при первом запросе. zapret — последним.
12. **Self-test** — `pidof` каждого демона, проверка сокетов `:53 :54 :1053 :3000 :9090`, наличие firewall-правила. FAIL → exit 1, state остаётся, откат через `uninstall.sh`.

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
| `/etc/nikki/run/profiles/main.yaml` | VLESS-профиль | нет | с `--remove-state` |
| `/opt/adguardhome/AdGuardHome.yaml` | конфиг AGH | нет | с `--remove-state` |
| `/opt/zapret/ipset/zapret-hosts-user.txt` | YouTube-домены | нет | с `--remove-state` |
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

Дефолтная NFQWS-стратегия — `fake,multisplit` + QUIC-fake. У части
провайдеров нужна другая:

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

- **mihomo fake-IP** подменяет только A-записи. AAAA проходит «как есть», поэтому v6-пункты назначения не попадают под правила `ru-blocked.list` / YouTube / geoip и идут мимо mihomo.
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
| mihomo не стартует после ребута | `logread \| grep nikki`. Обычно YAML-ошибка в `/etc/nikki/run/profiles/main.yaml` → править в LuCI → Nikki → Profile Editor |
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
