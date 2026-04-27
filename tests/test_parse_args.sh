#!/bin/sh
# Unit tests for parse_args() in install.sh.
#
# parse_args:
#   - заполняет VLESS_* / NFQWS_OPT / FLAG_* из CLI
#   - --no-adguard без --no-force-dns → refuse (exit non-zero)
#   - неизвестный флаг → usage + exit 2
#
# Usage: sh tests/test_parse_args.sh

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INSTALL_SH=$SCRIPT_DIR/install.sh

[ -f "$INSTALL_SH" ] || { echo "FATAL: $INSTALL_SH not found" >&2; exit 1; }

pass=0
fail=0

log_pass() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
log_fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; fail=$((fail + 1)); }

# Run parse_args + dump globals (or capture exit code).
_dump() {
    INSTALL_SH_TEST_MODE=1 sh -c '
        . "$1"
        shift
        parse_args "$@"
        for v in VLESS_URL VLESS_SERVER VLESS_PORT VLESS_UUID VLESS_PUBKEY \
                 VLESS_SID VLESS_SNI VLESS_FLOW VLESS_FP NFQWS_OPT \
                 FLAG_NO_ADGUARD FLAG_NO_ZAPRET FLAG_NO_I18N FLAG_NO_FORCE_DNS \
                 FLAG_FORCE_CONFIG FLAG_NON_INTERACTIVE; do
            eval "val=\$$v"
            printf "%s=%s\n" "$v" "$val"
        done
    ' _ "$INSTALL_SH" "$@" 2>/dev/null
}

assert_var() {
    _name=$1
    _dump_output=$2
    _expect_line=$3
    if printf '%s\n' "$_dump_output" | grep -Fxq "$_expect_line"; then
        log_pass "$_name"
    else
        log_fail "$_name" "expected line '$_expect_line' not in dump"
    fi
}

# --- 1. --vless-url single arg ---
out=$(_dump --vless-url 'vless://example')
assert_var 'vless_url_set' "$out" 'VLESS_URL=vless://example'

# --- 2. per-field overrides ---
out=$(_dump --vless-server 1.2.3.4 --vless-port 8443 --vless-uuid UUID --vless-pubkey KEY \
            --vless-sid SID --vless-sni sni.example --vless-flow xtls-rprx-vision --vless-fp chrome)
assert_var 'override_server'  "$out" 'VLESS_SERVER=1.2.3.4'
assert_var 'override_port'    "$out" 'VLESS_PORT=8443'
assert_var 'override_uuid'    "$out" 'VLESS_UUID=UUID'
assert_var 'override_pubkey'  "$out" 'VLESS_PUBKEY=KEY'
assert_var 'override_sid'     "$out" 'VLESS_SID=SID'
assert_var 'override_sni'     "$out" 'VLESS_SNI=sni.example'
assert_var 'override_flow'    "$out" 'VLESS_FLOW=xtls-rprx-vision'
assert_var 'override_fp'      "$out" 'VLESS_FP=chrome'

# --- 3. --nfqws-opt ---
out=$(_dump --nfqws-opt '--filter-tcp=443 --dpi-desync=fake')
assert_var 'nfqws_opt'        "$out" 'NFQWS_OPT=--filter-tcp=443 --dpi-desync=fake'

# --- 4. boolean flags ---
out=$(_dump --no-zapret --no-i18n --force-config --non-interactive)
assert_var 'flag_no_zapret'      "$out" 'FLAG_NO_ZAPRET=1'
assert_var 'flag_no_i18n'        "$out" 'FLAG_NO_I18N=1'
assert_var 'flag_force_config'   "$out" 'FLAG_FORCE_CONFIG=1'
assert_var 'flag_non_interactive' "$out" 'FLAG_NON_INTERACTIVE=1'
# не было передано — должны остаться 0
assert_var 'flag_no_zapret_default_off' "$(_dump --vless-url x)" 'FLAG_NO_ZAPRET=0'

# --- 5. --no-adguard БЕЗ --no-force-dns → refuse (non-zero exit) ---
INSTALL_SH_TEST_MODE=1 sh -c '
    . "$1"
    parse_args --no-adguard
' _ "$INSTALL_SH" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then log_pass 'no_adguard_without_no_force_dns_refuses'
else log_fail 'no_adguard_without_no_force_dns_refuses' "expected non-zero exit, got $rc"; fi

# --- 6. --no-adguard + --no-force-dns → ОК ---
INSTALL_SH_TEST_MODE=1 sh -c '
    . "$1"
    parse_args --no-adguard --no-force-dns
' _ "$INSTALL_SH" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then log_pass 'no_adguard_with_no_force_dns_ok'
else log_fail 'no_adguard_with_no_force_dns_ok' "expected 0, got $rc"; fi

# --- 7. unknown flag → exit 2 ---
INSTALL_SH_TEST_MODE=1 sh -c '
    . "$1"
    parse_args --bogus-flag
' _ "$INSTALL_SH" >/dev/null 2>&1
rc=$?
if [ "$rc" = "2" ]; then log_pass 'unknown_flag_exits_2'
else log_fail 'unknown_flag_exits_2' "expected exit 2, got $rc"; fi

# --- 8. -h / --help → exit 0 ---
INSTALL_SH_TEST_MODE=1 sh -c '. "$1"; parse_args --help' _ "$INSTALL_SH" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then log_pass 'help_exits_0'
else log_fail 'help_exits_0' "expected exit 0, got $rc"; fi

INSTALL_SH_TEST_MODE=1 sh -c '. "$1"; parse_args -h' _ "$INSTALL_SH" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then log_pass 'help_short_exits_0'
else log_fail 'help_short_exits_0' "expected exit 0, got $rc"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
