# Roadmap

Рабочий план развития OpenWrt Mihomo Gateway Installer. Список отражает
намерения, а не обещания. Приоритет — стабильность и предсказуемость, не
фичи ради фич.

---

## Near-term

- **OpenWrt 26.x support.** Расширить `SUPPORTED_RELEASES`, проверить apk/opkg
  детект, прогнать все 12 шагов pipeline на чистом образе.
- **CI.** `shellcheck -s sh` на install.sh + uninstall.sh, `sh -n` smoke-тест.
  GitHub Actions, без deploy-пайплайна.
- **IPv6 policy.** Явно задокументировать и протестировать поведение: сейчас
  mihomo fake-IP работает только для v4, v6 идёт в обход. Минимум — README
  с разбором, максимум — `--ipv6 {bypass,drop,route}` флаг.
- **Preflight VLESS URL.** Вытащить parser в отдельную функцию с unit-тестами
  на фикстурах (корректные + повреждённые URL).

## Mid-term

- **Per-client routing.** MAC/IP → тег правила в nikki profile. Нужна
  интеграция с dhcp host-файлом, UCI-секция в `/etc/config/nikki`.
- **Zapret NFQWS auto-tune.** Оболочка над `blockcheck.sh`, которая пишет
  подобранный NFQWS_OPT обратно в `/etc/config/zapret` без ручной правки
  LuCI. Параллельно — отдельная команда `reprobe` для периодической
  перепроверки.
- **Nikki subscription auto-update.** Cron-job + health-check после обновления:
  если mihomo не стартует, откат на предыдущий профиль. Требует отдельного
  snapshot-слота в backup-директории.
- **Multi-profile.** Поддержка нескольких VLESS URL с select-group в mihomo
  (выбор через LuCI или CLI).

## Out of scope

- Собственный GUI поверх LuCI. Есть `luci-app-nikki`, дублировать не будем.
- Multi-WAN / load-balancing. Отдельный класс задач, не вписывается в
  "три слоя транспарентного шлюза".
- Поддержка OpenWrt 23.x и старше. Матрица пакетников и ядер слишком тяжёлая.
- Xray / sing-box варианты. Проект сознательно построен на mihomo через nikki.
- Телеметрия, отправка логов куда-либо, online-обновление скрипта.

## Non-goals

- `--force` флагов, обходящих preflight refuse, не будет. Refuse — это фича.
- Автопочинки конфликтов на `:53` не будет. Выходим с понятной диагностикой.
- Auto-rollback после snapshot'а не будет. Симметричный uninstall.sh
  покрывает этот сценарий и остаётся единственным штатным путём отката.

## Known limitations

- `--force-config` пересевает `bind_port: 3000` в AdGuardHome.yaml — кастомный
  админ-порт, выставленный через wizard, сбрасывается. См. README.
- NFQWS_OPT для zapret — starting set. Для YouTube/SmartTV может требоваться
  ручная подстройка через `/opt/zapret/blockcheck.sh`.
- `uninstall.sh` не трогает extroot и swap. Это намеренно.
- Fail-fast: после снапшота (шаг 5) в случае ошибки автоматического отката
  нет. Только ручной `sh uninstall.sh`.
- DNS-redirect ловит только `udp/tcp :53`. DoH/DoT клиенты с хардкод-адресами
  (`1.1.1.1:443`) обходят AGH — нужен отдельный firewall-блок, сейчас не
  поставляется.

## Long-term

- **Recovery-режим.** Отдельный `rescue.sh`: перезапускает pipeline с
  последнего снапшота без удаления пакетов. Для ситуаций, когда mihomo
  упал после ребута, а `uninstall.sh` — слишком тяжёлая артиллерия.
- **Аудит-лог.** Единый журнал шагов pipeline в `/var/log/mihomo-gateway/`
  с ротацией через logrotate. Сейчас логи раскиданы по stdout и syslog.
- **Snapshot diff.** Утилита, показывающая что именно изменил install.sh
  поверх базового образа (UCI-диф + список новых файлов). Помогает
  диагностике на чужих устройствах.

## Testing

- **Матрица железа.** Netis N6 — reference, но нужен smoke-прогон на
  минимум одном MIPS и одном ARMv7 роутере, чтобы ловить pkg-менеджер и
  endianness-регрессии до релиза.
- **Fixture-based preflight.** Набор подготовленных `.config`-файлов и
  VLESS URL (валидные, битые, edge-case), прогоняемых через preflight
  без реального роутера.
- **Uninstall parity.** Тест, гарантирующий, что `uninstall.sh` возвращает
  систему в состояние "до install.sh" по списку изменённых UCI-секций и
  установленных пакетов. Diff-based, без ручной сверки.

## Release

- **Semver-теги.** `vMAJOR.MINOR.PATCH` на GitHub releases. MAJOR —
  breaking change в CLI-флагах или layout UCI. MINOR — новые шаги
  pipeline. PATCH — фиксы.
- **Changelog.** `CHANGELOG.md` с секциями per-release: Added / Changed /
  Fixed / Removed. Без автогенерации из commit messages — пишется руками
  на каждый тег.
- **Stable vs main.** `main` = текущая работа. Тег = протестированный
  срез. README ссылается на последний тег, а не на `main`.

## Contribution

- **Один PR — одна тема.** Refactor install.sh и новая фича —
  это два PR. Mixed PR отклоняются без обсуждения.
- **Preflight обязателен.** Любой новый шаг pipeline начинается с
  проверки предусловий и завершается симметричным откатом в
  `uninstall.sh`. Без этого PR не мёржится.
- **Комментарии — по делу.** Комментарий объясняет "почему", а не "что".
  Код, требующий комментария "что делает", переписывается.
