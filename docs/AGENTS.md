<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-27 | Updated: 2026-04-27 -->

# docs

## Purpose
Technical reference docs for operators and contributors — architecture, troubleshooting, design decisions. Operator-facing usage lives in `README.md` / `README_RU.md` at the repo root, not here.

## Key Files

| File | Description |
|------|-------------|
| `ARCHITECTURE.md` | Three-layer transparent gateway reference. Mermaid diagrams of fw4 + mihomo + zapret + AGH wiring, layer roles, DNS/routing flow. |
| `TROUBLESHOOTING.md` | Symptom → diagnosis → fix matrix. mihomo `/connections` API recipes, zapret config sync gotchas, AGH log-line interpretation, fake-IP filter pitfalls. |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `plans/` | Currently empty. Reserved for `superpowers:writing-plans` output and design proposals. |

## For AI Agents

### Working In This Directory

- These files are **technical reference**, not changelog or release notes. Update in place when behavior changes — don't append "as of YYYY-MM-DD" stamps.
- Architecture diagrams are Mermaid; verify they render in GitHub before committing (no exotic syntax).
- `TROUBLESHOOTING.md` recipes must be runnable as-is — paste the actual one-liner, not a paraphrase.
- Cross-link to user memory keys (`~/.claude/projects/.../memory/`) where the deeper context lives, but copy the actionable summary into the doc — readers shouldn't need memory access.

### Common Patterns

- Russian primary tone (matches `README_RU.md`); English allowed for log lines / API examples / file paths.
- One H2 per layer (mihomo / zapret / AGH / fw4) when describing a cross-cutting issue.
- No screenshots — terminal output blocks instead.

## Dependencies

### Internal
- `../README.md` / `../README_RU.md` — link target for "see operator docs"
- `../ROADMAP.md` — link target for "tracked on roadmap"
- `../install.sh` — source of truth for any constant cited (paths, ports, UCI keys)

<!-- MANUAL: -->
