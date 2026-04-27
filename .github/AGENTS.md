<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-27 | Updated: 2026-04-27 -->

# .github

## Purpose
GitHub-specific config — CI workflow, issue templates, PR template.

## Key Files

| File | Description |
|------|-------------|
| `workflows/ci.yml` | Three jobs on every push/PR to `main`: `shellcheck` (POSIX-strict lint of `install.sh` + `uninstall.sh`), `syntax` (`sh -n` and `dash -n` smoke), `unit-tests` (every `tests/test_*.sh` under both `sh` and `dash`). |
| `PULL_REQUEST_TEMPLATE.md` | Default PR body — links to `CONTRIBUTING.md`. |
| `ISSUE_TEMPLATE/bug_report.md` | Bug report scaffold (release / arch / steps / expected vs actual). |
| `ISSUE_TEMPLATE/feature_request.md` | Feature proposal scaffold. |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `workflows/` | GitHub Actions YAML files |
| `ISSUE_TEMPLATE/` | Issue scaffolds picked from "New Issue" UI |

## For AI Agents

### Working In This Directory

- CI runs are the only automated quality gate. Adding a new `tests/test_*.sh` requires a corresponding step in `unit-tests` (run with both `sh` and `dash`).
- `permissions: contents: read` is the minimum scope. Don't widen it without a documented reason.
- `dash` is the closest POSIX-strict reference shell available on `ubuntu-latest` runners — it stands in for BusyBox `ash`. Don't switch to `bash` to "fix" a failure; fix the script.
- Issue / PR templates: keep prompts minimal. The audience is a router operator filing a bug, not a software dev — ask for `cat /etc/openwrt_release`, package manager, output of the failing step.

### Testing CI Changes

```sh
# Local smoke before pushing
shellcheck -s sh install.sh uninstall.sh
sh -n install.sh && dash -n install.sh
sh -n uninstall.sh && dash -n uninstall.sh
for t in tests/test_*.sh; do sh "$t" && dash "$t" || exit 1; done
```

If all four classes pass locally, CI will pass too.

## Dependencies

### External
- `koalaman/shellcheck` (system package on `ubuntu-latest`)
- `dash` (apt package, installed in workflow steps)

<!-- MANUAL: -->
