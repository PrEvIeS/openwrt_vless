# OpenWrt Mihomo Gateway — установщик

Интерактивный установщик для роутера на **OpenWrt 25.12.2** (любая
архитектура, поддерживаемая nikki и zapret — allowlist в `install.sh`),
разворачивающий трёхслойный шлюз. Работает на всех архитектурах из
`SUPPORTED_ARCHES` (MIPS / aarch64 / arm / x86_64 / i386):

- **mihomo** (через пакет `nikki` + `luci-app-nikki`) — VLESS + Reality транспорт
  для заблокированных в РФ ресурсов, fake-IP DNS, правилам на `ru-blocked.list`
- **zapret** (через дистрибутив remittor) — DPI-обход для YouTube/SmartTV
  **без VPN** (нормальный пинг, прямая маршрутизация)
- **AdGuard Home** — фильтрация рекламы/трекеров/телеметрии для всей LAN
- **DNS interception** (firewall DNAT :53) — принудительный DNS для SmartTV
  и прочих устройств, которые пытаются использовать сторонние резолверы

Итоговая маршрутизация:
- `*.ru / *.рф / *.su / GEOIP,RU` → **DIRECT**
- YouTube и его CDN → **DIRECT + zapret DPI-bypass**
- `ru-blocked.list` (runetfreedom) → **VLESS-Reality → VPS**
- Всё остальное → **FINAL** (по умолчанию VLESS, перекидывается в LuCI)

---

## Требования

| Параметр | Значение |
|---|---|
| OpenWrt | **строго 25.12.2** (проверяется pre-flight'ом) |
| Архитектура | любая из `SUPPORTED_ARCHES`: `mipsel_24kc`, `aarch64_cortex-a53/-a72/-generic`, `arm_cortex-a7/-a7_neon-vfpv4/-a9/-a15_neon-vfpv4`, `x86_64`, `i386_pentium4`, `i386_pentium-mmx`. Список поддержан апстримами nikki+zapret |
| Пакетник | **только `apk`** (не `opkg`) |
| RAM | ≥ 200 MB (на роутерах с 256 MB стек работает впритык) |
| extroot | **обязателен** — `/overlay` на ext4-разделе USB/SD/NVMe, ≥ 2 ГБ |
| swap | **обязателен** — активный swap ≥ 1 ГБ (рекомендуется 1.5 ГБ) |
| Флешка | 32 ГБ USB 3.0, надёжного бренда (SanDisk Ultra, Samsung Fit и т. п.) |
| VLESS-сервер | поднят; URL формата `vless://UUID@host:port?type=tcp&security=reality&pbk=...&sni=...&sid=...&flow=xtls-rprx-vision&fp=chrome#label` |
| Интернет | работающий WAN на роутере |
| Доступ | root SSH |

**Несоответствия preflight'а → exit 2, без мутаций.** Никакого `--force`
escape-hatch'а. Архитектура не хардкодится — проверяется против allowlist'а;
фактические `.apk`-пакеты nikki и zapret скачают сами через свои
инсталляционные скрипты (они детектят `DISTRIB_ARCH` автоматически).

---

## Что сделать ДО запуска (вручную)

Установщик **не выполняет** подготовку роутера — только слой сервисов поверх
чистого extroot. Перед запуском:

### 1. Прошивка OpenWrt 25.12.2

1. Идёте на <https://firmware-selector.openwrt.org/>, ищете модель вашего
   роутера, скачиваете **factory-образ** (первая прошивка должна быть
   factory, не sysupgrade).
2. Заходите в стоковый веб-интерфейс роутера (`192.168.1.1`, пароль на
   наклейке), System Tools → Upgrade → выбираете factory-образ OpenWrt,
   прошиваете.
3. После ребута: `192.168.1.1` отвечает LuCI без пароля. Задайте root-пароль.
4. Проверьте: `cat /etc/openwrt_release` → `DISTRIB_RELEASE='25.12.2'`,
   `DISTRIB_ARCH` из `SUPPORTED_ARCHES`.
5. Настройте WAN и Wi-Fi через LuCI.

### 2. extroot + swap

1. На ПК отформатируйте 32 ГБ флешку в **две партиции**:
   - `/dev/sda1` — 1.5 ГБ, тип Linux swap
   - `/dev/sda2` — остальное, ext4
2. Воткните в USB 3.0 порт роутера, подключитесь по SSH.
3. Установите драйверы (установщик это сделает повторно, но extroot нужен
   заранее):
   ```sh
   apk update
   apk add block-mount e2fsprogs kmod-fs-ext4 kmod-usb-storage kmod-usb-storage-uas kmod-usb3
   block info   # должен показать sda1 (swap) и sda2 (ext4)
   ```
4. В LuCI → System → Mount Points:
   - `/dev/sda2` → Enabled, Target **Use as external overlay (/overlay)**
   - `/dev/sda1` → Swap Enabled
   - Save & Apply → `reboot`
5. После ребута проверьте:
   ```sh
   df -h           # /overlay должен быть на sda2 с десятками ГБ
   free -m         # Swap: ~1500 MB активен
   ```

Без этого preflight установщика откажет с `refuse` (exit 2).

---

## Запуск установщика

### Интерактивно

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/PrEvIeS/openwrt_vless/main/install.sh
sh /tmp/install.sh
```

Скрипт попросит **одну** строку — VLESS URL (как выдают панели типа 3x-ui,
marzban, x-ui и пр.). Парсер сам извлечёт `UUID`, `server`, `port`,
`public-key`, `short-id`, `sni`, `flow`, `fp`, `network`, `security`.

### Non-interactive

```sh
sh install.sh --non-interactive \
    --vless-url 'vless://UUID@your-vps.example.com:443?type=tcp&encryption=none&security=reality&pbk=REALITY_PUBLIC_KEY&fp=chrome&sni=www.google.com&sid=SHORT_ID&spx=%2F&flow=xtls-rprx-vision#label'
```

Кавычки обязательны (`&` и `?` — метасимволы шелла). `#fragment` в URL
игнорируется (это label от панели).

### Override отдельных полей

Если URL задаёт не то значение, что нужно — перезапишите отдельным флагом.
Приоритет: **override-флаг > URL > fallback-default**.

```sh
sh install.sh \
    --vless-url 'vless://.../' \
    --vless-sni my.cdn.example.com   # перезапишет sni из URL
```

### Полный список флагов

```
VLESS:
  --vless-url URL        основной вход (vless://...)

  override отдельных полей (перезаписывают значения из URL):
  --vless-server HOST    --vless-port N
  --vless-uuid UUID      --vless-pubkey KEY (reality pbk)
  --vless-sid HEX        --vless-sni HOST
  --vless-flow NAME      --vless-fp NAME

Zapret:
  --nfqws-opt "..."      стратегия для NFQWS_OPT
                         (дефолт — стартовая из §5 ниже; может потребовать
                          blockcheck для вашего провайдера)
  --no-zapret            не устанавливать zapret

AdGuard Home:
  --no-adguard           не устанавливать AGH
  --force-config         перезаписать AdGuardHome.yaml / nikki-profile

Прочее:
  --no-force-dns         не добавлять firewall-правило Force DNS
  --no-i18n              не ставить luci-i18n-nikki-ru
  --non-interactive      die вместо prompt'а при пустом --vless-url
```

### Fallback-дефолты (если в URL отсутствуют)

| Поле | Default |
|---|---|
| port | 443 |
| sni | `www.google.com` |
| flow | `xtls-rprx-vision` |
| fp | `chrome` |
| type (network) | `tcp` |
| security | `reality` (другие значения → die) |

---

## Что делает установщик (12 шагов)

1. **Preflight release + arch** — `DISTRIB_RELEASE=25.12.2` обязательно;
   `DISTRIB_ARCH` ∈ `SUPPORTED_ARCHES` (allowlist nikki+zapret). Детектированные
   `DETECTED_ARCH` и `DETECTED_TARGET` печатаются в итоговом summary.
2. **Preflight extroot** — `/overlay` на `/dev/sd*p*`, `/dev/mmcblk*p*` или
   `/dev/nvme*p*` ≥ 2 ГБ + активный swap ≥ 1 ГБ.
3. **Preflight conflicts** — нет xray/sing-box/passwall/podkop; LAN = `br-lan`;
   `:53` держит либо `dnsmasq`, либо никто; есть интернет.
4. **Сбор VLESS URL → парсинг → валидация** — `vless://UUID@host:port?...#label`
   → поля `server/port/uuid/pbk/sid/sni/flow/fp/network/security`. Приоритет:
   override-флаг > URL > fallback-default. Валидация каждого поля строгая
   (защита от YAML-injection в профиль mihomo).
5. **Snapshot state** — `snapshot.env` (UCI-значения для symbolic restore)
   + копии `/etc/config/{network,dhcp,firewall}` + nftables ruleset + crontab,
   всё в `/root/openwrt-mihomo-backup/` (chmod 700).
6. **apk add** базовые — `curl ca-bundle block-mount e2fsprogs kmod-*`.
7. **nikki** — скачиваем feed.sh от `nikkinikki-org/OpenWrt-nikki`, добавляем
   репозиторий, ставим `nikki luci-app-nikki luci-i18n-nikki-ru`.
8. **zapret** — запускаем `update-pkg.sh` от remittor, ставим `zapret` +
   `luci-app-zapret` под `mipsel_24kc`.
9. **AdGuard Home** — `apk add adguardhome`, workdir = `/opt/adguardhome`.
10. **Конфигурация**:
    - генерация `/etc/nikki/run/profiles/main.yaml` с VLESS-параметрами,
      fake-ip DNS на `:1053`, правилами RU→DIRECT + YouTube→YOUTUBE +
      `ru-blocked.list` (runetfreedom) → PROXY
    - UCI `nikki.config.enabled=1`, `mode=redir_tun`
    - UCI `zapret.config` — `mode=nfqws`, `mode_filter=hostlist`,
      `nfqws_tcp_port=80,443`, `nfqws_udp_port=443`, `disable_ipv6=1`,
      `nfqws_opt=<стратегия>`
    - `/opt/zapret/ipset/zapret-hosts-user.txt` — 10 YouTube-доменов
    - dnsmasq → `:54`, dhcp.lan.dhcp_option = `[3,$LAN_IP]`, `[6,$LAN_IP]`,
      `[15,lan]`, `expandhosts=1`, `cachesize=0`, `noresolv=1`
    - `/opt/adguardhome/AdGuardHome.yaml` — пре-сидированный конфиг
      (upstreams: `[/lan/]127.0.0.1:54`, `[/pool.ntp.org/]1.1.1.1/1.0.0.1`,
      `127.0.0.1:1053`; bootstrap `1.1.1.1 8.8.8.8`; фильтры
      `AdGuard DNS filter`, `AdGuard Russian filter`,
      `HaGeZi Encrypted DNS/VPN/TOR/Proxy Bypass`; retention 24h/720h;
      `users: []` — пароль задаёт мастер)
    - firewall redirect `Force DNS`: `lan:53 → $LAN_IP:53 (tcpudp)`
11. **Service order fix + enable + start** — `S50nikki → S60adguardhome →
    S99zapret`.
12. **Self-test** — pidof каждого демона, наличие сокетов `:53 :54 :1053 :3000
    :9090`, наличие firewall-правила.

**После успешного selftest'а** — напечатается инструкция: открыть
`http://LAN_IP:3000` (мастер AGH для пароля) + при необходимости запустить
`/opt/zapret/blockcheck.sh` для подбора NFQWS-стратегии под вашего провайдера.

---

## Ручные шаги после установки

### AGH wizard (обязательно — пароль)

`http://LAN_IP:3000` →

- Admin Web Interface: LAN_IP, port **8080**
- DNS Server: All interfaces, port **53**
- Логин/пароль — придумайте крепкий. **Пароль не сохраняется** никем кроме
  вас (bcrypt в BusyBox нет — автосеять не можем).

Проверьте `Settings → DNS Settings`: upstreams уже пре-сидированы, но если
что, порядок должен быть:

```
[/lan/]127.0.0.1:54
[/pool.ntp.org/]1.1.1.1
[/pool.ntp.org/]1.0.0.1
127.0.0.1:1053
```

### blockcheck (если YouTube тормозит)

Дефолтная NFQWS-стратегия — `--dpi-desync=fake,multisplit` + QUIC-fake
(см. `DEFAULT_NFQWS_OPT` в `install.sh`). У некоторых провайдеров нужна
другая. Проверка:

```sh
service zapret stop
/opt/zapret/blockcheck.sh
```

Выбор: `https + quic`, level=`standard`, curl-mode=`curl`, target=`youtube.com`.
10–20 минут → скопируйте лучшую стратегию → обновите `NFQWS_OPT` в LuCI →
Services → Zapret → Settings.

---

## Проверка (после установки)

```sh
# на роутере
ping 1.1.1.1
free -m                     # swap активен
df -h                       # overlay на USB

# с клиента в LAN
nslookup youtube.com LAN_IP     # → fake-IP 198.18.x.x = mihomo отработал
nslookup yandex.ru LAN_IP       # → реальный IP (yandex DoH)
nslookup doubleclick.net LAN_IP # → 0.0.0.0 (AGH заблокировал)

# с клиента (браузер)
https://ifconfig.me             # → IP VPS (VLESS работает)
https://yandex.ru/internet      # → ваш домашний IP (RU напрямую)
https://www.youtube.com         # → открывается без замедления
```

---

## Удаление

```sh
sh uninstall.sh                                          # минимум — stop + UCI-restore
sh uninstall.sh --remove-packages --remove-state         # полная очистка пакетов и /opt
sh uninstall.sh --restore-crontab                        # вернуть crontab из snapshot
```

- UCI-значения восстанавливаются **символьно** из `snapshot.env`
  (не перезаписываются файлы конфигурации — чтобы не затереть правки,
  сделанные пользователем после установки).
- `/overlay` и swap **не трогаются** никогда.
- Прошивка OpenWrt не откатывается — для возврата на стоковую прошивку
  используйте U-Boot web recovery вашего роутера (обычно `http://192.168.1.1/`
  после reset+power), если он это поддерживает.

---

## Режимы сбоев (fail-fast)

| Exit | Когда | Что делать |
|---|---|---|
| 0 | self-test пройден | — |
| 2 | preflight отказ (release / extroot / conflicts / VLESS-params) | исправить среду по сообщению, запустить снова |
| 1 | ошибка после начала мутаций (snapshot создан) | `sh uninstall.sh`, разобраться в причине |

Никакого auto-rollback, никаких retry, никаких `--force`. Preflight
refuse — симметрично self-test'у: одна и та же строгость на входе и
выходе. Откат — только через отдельный `uninstall.sh`.

---

## Архитектура (DNS + трафик)

```
[Клиенты LAN, включая Smart TV]
    │  (Wi-Fi / Ethernet)
    ▼
┌─────────────────────────────────────────┐
│  OpenWrt 25.12.2 router                 │
├─────────────────────────────────────────┤
│                                         │
│  DNS:                                   │
│  ├─ firewall DNAT :53  (принудительно)  │
│  ├─ AGH        :53     (фильтр + лог)   │
│  ├─ mihomo     :1053   (fake-ip + rules)│
│  └─ dnsmasq    :54     (только .lan)    │
│                                         │
│  Трафик:                                │
│  ├─ mihomo TProxy → DIRECT или VPN      │
│  ├─ VLESS-Reality → VPS (blocked)       │
│  └─ zapret nfqws → DPI-обход YouTube    │
│                                         │
│  Управление:                            │
│  ├─ LuCI        :80                     │
│  ├─ AGH UI      :8080                   │
│  └─ mihomo UI   через LuCI → Nikki      │
│                                         │
└─────────────────────────────────────────┘
    │
    ▼
[WAN → провайдер]
    │
    ├── напрямую: RU-трафик + YouTube (через zapret)
    └── через VPS: заблокированные в РФ
```

---

## Типовые проблемы

| Симптом | Причина / решение |
|---|---|
| `mihomo` не стартует после ребута | `logread \| grep nikki`. Обычно YAML-ошибка в `/etc/nikki/run/profiles/main.yaml` — правьте через LuCI → Nikki → Profile Editor (там подсветка) |
| YouTube работает в браузере, не на SmartTV | DNS interception включён? (`uci show firewall \| grep "Force DNS"`). QUIC в NFQWS_OPT? IPv6 отключён на LAN? |
| Госуслуги/банки не работают | `mode_filter=hostlist` обязателен — zapret режет TLS только хостам из `zapret-hosts-user.txt`. Проверь `uci get zapret.config.mode_filter` |
| RAM ≥ 90% | Откл. лишние блоклисты в AGH, retention query log меньше, `--no-i18n` при переустановке. На роутерах с 256 MB RAM — держитесь 3-4 блоклистов максимум |
| VLESS медленный | CPU-потолок слабого SoC (MT7621 и родственники) ~70-80 Мбит/с через VLESS-Reality. Это упирается в железо; для больших скоростей нужен роутер помощнее (aarch64 / x86_64) |

Full troubleshooting — в комментариях `install.sh` и логах `/var/log/`.

---

## Лицензия

Скрипты — MIT. Сторонние пакеты — по лицензиям своих проектов
(mihomo/nikki/zapret/AdGuardHome).
