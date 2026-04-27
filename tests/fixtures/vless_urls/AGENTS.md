<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-27 | Updated: 2026-04-27 -->

# vless_urls

## Purpose
Fixture data for `tests/test_vless_url.sh`. Each `*.url` file contains exactly one line — a VLESS+Reality URL fed to `parse_vless_url()`.

## Layout

| Path | Behavior |
|------|----------|
| `valid/NN_name.url` | Parser must exit 0. |
| `valid/NN_name.expect` | KEY=VALUE per line — every key must match the corresponding global after parse (partial assertion: extra globals are ignored). |
| `broken/NN_name.url` | Parser must die (non-zero exit). No `.expect` file. |

## Current Coverage

| Fixture | Asserts |
|---------|---------|
| `valid/01_full.url` | All fields present, happy path |
| `valid/02_no_fragment.url` | Trailing `#label` optional |
| `valid/03_percent_encoded_sni.url` | `%XX` decoding via `_urldecode()` |
| `valid/04_unknown_params_ignored.url` | Unknown query params don't break parser |
| `valid/05_plus_as_space_in_sni.url` | `+` → space substitution in SNI |
| `valid/06_no_port.url` | Port defaults to `VLESS_PORT_DEFAULT=443` |
| `valid/07_ipv4_server.url` | Bare IPv4 host (no DNS name) |
| `valid/08_minimal.url` | Only required fields supplied |
| `broken/01_wrong_scheme.url` | Not `vless://` → reject |
| `broken/02_no_at_sign.url` | Missing `@` separator → reject |
| `broken/03_empty.url` | Empty input → reject |
| `broken/04_only_scheme.url` | `vless://` with no body → reject |

## For AI Agents

### Adding a Fixture

1. Drop the `.url` file (one line, no trailing newlines beyond one). Use sequential `NN_name` numbering.
2. For valid fixtures, add a sibling `.expect` listing only the keys you want to assert. The runner ignores extra globals — focus on what's distinctive about this case.
3. Run `sh tests/test_vless_url.sh` to confirm it picks up the new file.
4. Never put a real UUID / pubkey / SID in a fixture — use placeholders like `11111111-...-555555555555` and `PUBKEY123`.

<!-- MANUAL: -->
