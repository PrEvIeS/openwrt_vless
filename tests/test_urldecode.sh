#!/bin/sh
# Unit tests for _urldecode() in install.sh.
#
# _urldecode handles application/x-www-form-urlencoded inputs:
#   - '+' → space
#   - '%HH' → byte (hex two-digit)
#   - всё остальное passthrough
#
# Critical: must work identically на BusyBox ash (target) и dash (CI),
# поэтому реализация использует printf "\NNN" octal, не "\xHH".
#
# Usage: sh tests/test_urldecode.sh

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INSTALL_SH=$SCRIPT_DIR/install.sh

[ -f "$INSTALL_SH" ] || { echo "FATAL: $INSTALL_SH not found" >&2; exit 1; }

pass=0
fail=0

# Run _urldecode in subshell so install.sh state doesn't leak.
_decode() {
    INSTALL_SH_TEST_MODE=1 sh -c '
        . "$1"
        _urldecode "$2"
    ' _ "$INSTALL_SH" "$1"
}

assert_eq() {
    _name=$1
    _input=$2
    _want=$3
    _got=$(_decode "$_input")
    if [ "$_got" = "$_want" ]; then
        printf '  PASS  %s\n' "$_name"
        pass=$((pass + 1))
    else
        printf "  FAIL  %s\n        input='%s'\n        want ='%s'\n        got  ='%s'\n" \
            "$_name" "$_input" "$_want" "$_got"
        fail=$((fail + 1))
    fi
}

# --- ASCII passthrough ---
assert_eq 'ascii_passthrough'   'hello'              'hello'
assert_eq 'empty_string'        ''                   ''
assert_eq 'symbols_passthrough' '.-_~'               '.-_~'

# --- '+' → space ---
assert_eq 'plus_to_space'       'hello+world'        'hello world'
assert_eq 'multiple_pluses'     'a+b+c'              'a b c'
assert_eq 'leading_plus'        '+leading'           ' leading'
assert_eq 'trailing_plus'       'trailing+'          'trailing '

# --- %HH single-byte ---
assert_eq 'percent_space'       'foo%20bar'          'foo bar'
assert_eq 'percent_plus'        '%2B'                '+'
assert_eq 'percent_slash'       'a%2Fb'              'a/b'
assert_eq 'percent_lowercase'   'a%2fb'              'a/b'
assert_eq 'percent_at'          'user%40host'        'user@host'
assert_eq 'percent_question'    'a%3Fb'              'a?b'
assert_eq 'percent_equals'      'a%3Db'              'a=b'

# --- mixed cases ---
assert_eq 'mixed_plus_percent'  'hello+world%21'     'hello world!'
assert_eq 'sni_typical'         'www.google.com'     'www.google.com'
assert_eq 'sni_encoded_dot'     'www%2Egoogle%2Ecom' 'www.google.com'

# --- multi-byte UTF-8 (cyrillic 'р' = U+0440 = 0xD1 0x80) ---
# Если printf не схлопывает многобайтовый UTF-8 правильно, длина в байтах
# отличается от ожидаемой. Сравниваем по длине и по точному совпадению.
assert_eq 'utf8_cyrillic_r'     '%D1%80'             "$(printf '\321\200')"

# --- edge: lone '%' без двух hex после — passthrough (parser не должен крашить) ---
# Реализация трогает только %[0-9A-Fa-f][0-9A-Fa-f], одиночный '%' попадает в
# default-ветку через case как обычный символ.
assert_eq 'lone_percent'        '50%'                '50%'
assert_eq 'percent_one_hex'     '%A'                 '%A'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
