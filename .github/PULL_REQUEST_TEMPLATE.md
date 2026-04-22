## Что меняется

Одно-два предложения. Список файлов по категории (feat / fix / docs /
refactor / test / chore).

## Зачем

Ссылка на issue или обоснование. Если рефакторинг — что именно стало
лучше (измеримо или хотя бы читаемо).

## Как тестировалось

- [ ] `shellcheck -s sh install.sh uninstall.sh` — чисто
- [ ] `sh -n install.sh && sh -n uninstall.sh` — синтаксис OK
- [ ] Прогон на реальном роутере (указать модель и OpenWrt релиз):
- [ ] Self-test (шаг 12) прошёл после install.sh
- [ ] `uninstall.sh` вернул систему в baseline (diff pkg/uci пуст или
      объяснён)
- [ ] Docs-only PR — отметить, что прогон не требовался

## Scope

- [ ] Один PR — одна тема (нет смешанных изменений)
- [ ] Не попадает в `ROADMAP.md §Out of scope`
- [ ] Не противоречит `ROADMAP.md §Non-goals`
- [ ] Новый шаг pipeline имеет симметричный откат в `uninstall.sh`
      (N/A если нет новых шагов)

## Breaking changes

- [ ] CLI-флаги: изменены / убраны / переименованы (если да — перечисли)
- [ ] UCI layout: изменён (если да — что именно и как мигрирует)
- [ ] Snapshot format: изменён (если да — совместимость со старыми
      snapshot'ами)

Если любой из пунктов отмечен — PR требует bump MAJOR и запись в
`CHANGELOG.md §Unreleased`.

## Checklist

- [ ] `CHANGELOG.md` обновлён (секция Unreleased)
- [ ] `ROADMAP.md` обновлён, если фича закрывает roadmap-пункт
- [ ] Нет `Co-Authored-By: Claude` / подобных AI-co-author тегов
- [ ] Без emoji в коде, коммитах, комментариях
