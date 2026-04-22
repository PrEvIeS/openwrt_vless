---
name: Feature request
about: Proposal for a new flag, pipeline step, or behavior change
title: 'feat: '
labels: enhancement
---

## Problem

Что сейчас не получается сделать / делается неудобно. **Юзкейс из жизни**,
не "было бы хорошо иметь".

## Proposal

Что конкретно предлагается. CLI-флаг / шаг pipeline / новая секция UCI.
Формат вызова:

```sh
sh install.sh --new-flag=value
```

## Scope check

Проверь, что фича **не попадает** в `ROADMAP.md §Out of scope`:

- [ ] Не GUI поверх LuCI
- [ ] Не multi-WAN / load-balancing
- [ ] Не поддержка OpenWrt 23.x и старше
- [ ] Не Xray / sing-box замена mihomo
- [ ] Не телеметрия / online-обновление

И **не противоречит** `ROADMAP.md §Non-goals`:

- [ ] Не `--force` флаг, обходящий preflight refuse
- [ ] Не автопочинка конфликтов на `:53`
- [ ] Не auto-rollback после снапшота

Если какой-то чекбокс не проставлен — объясни в PR, почему случай
исключительный.

## Install/uninstall symmetry

Любой новый шаг pipeline обязан иметь откат в `uninstall.sh`. Набросок
отката:

```sh
# в uninstall.sh:
...
```

## Testing

Как проверить, что фича работает, и что она не ломает baseline:

-
-

## Alternatives

Что рассматривал(а) и почему отбросил(а). Ссылки на upstream решения,
если есть.
