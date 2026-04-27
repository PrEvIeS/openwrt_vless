# Contributing

Правила короткие. Читать целиком перед PR.

## Принципы

- **Fail-fast поверх tolerant.** Preflight refuse — фича, не баг. `--force`
  флагов, обходящих refuse, не будет.
- **Симметрия install/uninstall.** Любой новый шаг pipeline в `install.sh`
  обязан иметь откат в `uninstall.sh`. Без этого PR не мёржится.
- **Snapshot-first.** Мутация системы начинается только после снапшота
  (шаг 5). Всё, что до снапшота — только preflight-проверки.
- **Минимализм.** Три похожих строки лучше преждевременной абстракции.
  Helper ради одного вызова — нет.

## Правила PR

- **Один PR — одна тема.** Рефакторинг и новая фича = два PR. Mixed PR
  закрывается без ревью.
- **Заголовок в imperative mood.** `add IPv6 bypass flag`, не
  `added IPv6 bypass flag`.
- **Prefix по типу изменения:**
  - `feat:` — новый функционал
  - `fix:` — баг
  - `docs:` — только документация
  - `refactor:` — без изменения поведения
  - `test:` — тесты
  - `chore:` — зависимости, CI, tooling
- **Тело коммита объясняет "почему", не "что".** Diff покажет "что".
- **Без co-author для AI.** Не добавлять `Co-Authored-By: Claude` и подобное.

## Требования к коду

### shell (install.sh / uninstall.sh)

- **POSIX `sh`**, не bash. `#!/bin/sh` сверху. Никаких `[[ ]]`, `$'...'`,
  массивов, `local`.
- **`set -eu`** обязательно. Ошибки не глотать — выходить с понятной
  диагностикой.
- **`shellcheck -s sh` clean.** CI это проверит. Отключать правила только
  с inline-комментарием и обоснованием.
- **Indent = 4 spaces**, не табы.
- **Кавычки везде.** `"$var"`, не `$var`. Исключение — цельночисловые
  сравнения в `[ ]`.
- **Переменные UPPER_CASE** для глобалов, `lower_case` для локальных
  функций (даже без `local`).
- **Функции — глагол от существительного.** `preflight_release`,
  `snapshot_uci`, `configure_nikki`.

### документация

- **RU для user-facing** (README_RU, TROUBLESHOOTING, CONTRIBUTING).
- **EN для technical** (README, ARCHITECTURE, CHANGELOG, LICENSE, SECURITY).
- **Wrap ~80-90 cols** для читаемости в терминале. Code blocks —
  без wrap.
- **Без emoji.** В коде, коммитах, документации.

### комментарии в коде

- Комментарий объясняет **почему**, а не **что**.
- Код, требующий комментария "что делает", переписывается в понятный.
- Ссылки на upstream issues / PRs приветствуются: `# see openwrt/openwrt#12345`.

## Workflow

1. **Issue first.** Открыть issue через шаблон `.github/ISSUE_TEMPLATE/`
   до написания кода. Для тривиального тайпа — можно без issue, но PR
   должен объяснять всё в описании.
2. **Ветка = `type/short-slug`:** `feat/ipv6-policy`, `fix/stop-cron-marker`.
3. **Локальная проверка перед push:**
   ```sh
   shellcheck -s sh install.sh uninstall.sh
   sh -n install.sh && sh -n uninstall.sh
   ```
4. **Прогнать на реальном роутере** (минимум — Netis N6 reference) если
   меняется pipeline. Docs-only PR — без прогона.
5. **PR через шаблон.** Заполнить секции "Что меняется", "Зачем",
   "Как тестировалось".

## Testing

Юнит-тесты (POSIX `sh` + `dash`, без зависимостей) лежат в `tests/`:

| Скрипт | Покрытие |
|---|---|
| `tests/test_vless_url.sh` | `parse_vless_url()` через fixtures (`tests/fixtures/vless_urls/{valid,invalid}/*`) |
| `tests/test_urldecode.sh` | `_urldecode()` — `+` → space, `%HH`, UTF-8, edge-cases |
| `tests/test_state_file.sh` | `state_mark_done`/`state_check_done`/`should_skip_step`/`state_clear_all` |
| `tests/test_parse_args.sh` | CLI-флаги, конфликт `--no-adguard` без `--no-force-dns`, exit codes |

Локально перед PR:

```sh
shellcheck -s sh install.sh uninstall.sh
sh -n install.sh && sh -n uninstall.sh
sh   tests/test_vless_url.sh tests/test_urldecode.sh tests/test_state_file.sh tests/test_parse_args.sh
dash tests/test_vless_url.sh tests/test_urldecode.sh tests/test_state_file.sh tests/test_parse_args.sh
```

CI (`.github/workflows/ci.yml`) гоняет всё это на каждый push/PR.

End-to-end на реальном роутере (минимум — Netis N6 или Cudy TR3000 v1) если меняется pipeline:

- `sh install.sh --non-interactive --vless-url '...'` на чистом образе.
- `sh uninstall.sh` сразу после — проверить, что `opkg list-installed` /
  `apk info` вернулись к исходному набору, UCI-секции восстановлены.
- Self-test pipeline (шаг 16) должен пройти без ручных действий кроме
  AGH wizard.

Diff pre/post install:
```sh
# до install
opkg list-installed > /tmp/pkg.before
uci export > /tmp/uci.before

# install + uninstall

# после uninstall
opkg list-installed > /tmp/pkg.after
uci export > /tmp/uci.after
diff /tmp/pkg.before /tmp/pkg.after
diff /tmp/uci.before /tmp/uci.after
```

Разница должна быть пуста (или объяснена в PR).

## Scope вне проекта

См. `ROADMAP.md §Out of scope` — туда не добавляем:
- GUI поверх LuCI.
- Multi-WAN / load-balancing.
- OpenWrt 23.x и старше.
- Xray / sing-box варианты.
- Телеметрия, online-обновление скрипта.

PR в эти направления закрывается без обсуждения.

## Security-чувствительные изменения

Любая правка firewall-rules, DNS-redirect, iptables/nftables — требует:
1. Объяснения threat model в описании PR.
2. Теста, что baseline traffic (HTTP/HTTPS/DNS) не ломается.
3. Проверки на leak (DNS, IPv6 при `--no-ipv6-bypass`, если это
   появится).

Подробнее — см. `SECURITY.md`.
