#!/bin/sh
# Fixture-based tests for parse_vless_url() in install.sh.
#
# Usage: sh tests/test_vless_url.sh
#
# Sources install.sh with INSTALL_SH_TEST_MODE=1 to skip main(), then invokes
# parse_vless_url() against fixtures under tests/fixtures/vless_urls/.
#
# valid/*.url + *.expect pairs:
#   - parser must succeed (exit 0)
#   - every KEY=VALUE line in *.expect must match the corresponding global
#     after parse (ignores keys not listed — partial assertions OK).
#
# broken/*.url:
#   - parser must die (non-zero exit).
#
# Exit codes: 0 — all tests pass, 1 — any failure.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INSTALL_SH=$SCRIPT_DIR/install.sh
FIXTURES_DIR=$SCRIPT_DIR/tests/fixtures/vless_urls

[ -f "$INSTALL_SH" ] || { echo "FATAL: $INSTALL_SH not found" >&2; exit 1; }
[ -d "$FIXTURES_DIR" ] || { echo "FATAL: $FIXTURES_DIR not found" >&2; exit 1; }

pass=0
fail=0

log_pass() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
log_fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; fail=$((fail + 1)); }

# --- valid fixtures ---
for url_file in "$FIXTURES_DIR"/valid/*.url; do
    [ -f "$url_file" ] || continue
    name=$(basename "$url_file" .url)
    expect_file=${url_file%.url}.expect
    url=$(head -n 1 "$url_file")

    if [ ! -f "$expect_file" ]; then
        log_fail "valid/$name" "missing .expect companion file"
        continue
    fi

    # Run parser in subshell. Echo VLESS_* globals so we can diff.
    # shellcheck disable=SC2016
    actual=$(
        INSTALL_SH_TEST_MODE=1 sh -c '
            . "$1"
            parse_vless_url "$2" || exit 9
            for v in VLESS_UUID VLESS_SERVER VLESS_PORT VLESS_PUBKEY \
                     VLESS_SNI VLESS_SID VLESS_FLOW VLESS_FP \
                     VLESS_NETWORK VLESS_SECURITY; do
                eval "val=\$$v"
                printf "%s=%s\n" "$v" "$val"
            done
        ' _ "$INSTALL_SH" "$url" 2>/dev/null
    )
    rc=$?

    if [ "$rc" -ne 0 ]; then
        log_fail "valid/$name" "parser exited $rc on a valid URL"
        continue
    fi

    ok=1
    while IFS= read -r want || [ -n "$want" ]; do
        [ -z "$want" ] && continue
        case "$want" in
            \#*) continue ;;
        esac
        # match exact line in actual
        if ! printf '%s\n' "$actual" | grep -Fxq "$want"; then
            log_fail "valid/$name" "expected '$want' not produced by parser"
            ok=0
        fi
    done <"$expect_file"

    [ "$ok" -eq 1 ] && log_pass "valid/$name"
done

# --- broken fixtures ---
for url_file in "$FIXTURES_DIR"/broken/*.url; do
    [ -f "$url_file" ] || continue
    name=$(basename "$url_file" .url)
    url=$(head -n 1 "$url_file")

    # shellcheck disable=SC2016
    INSTALL_SH_TEST_MODE=1 sh -c '
        . "$1"
        parse_vless_url "$2"
    ' _ "$INSTALL_SH" "$url" >/dev/null 2>&1
    rc=$?

    if [ "$rc" -eq 0 ]; then
        log_fail "broken/$name" "parser accepted an invalid URL (expected non-zero exit)"
    else
        log_pass "broken/$name"
    fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
