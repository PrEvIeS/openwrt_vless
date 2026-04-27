#!/bin/sh
# Unit tests for state-file functions in install.sh:
#   state_mark_done, state_check_done, should_skip_step, state_clear_all
#
# State-file (SETUP_STATE_FILE) обеспечивает идемпотентность шагов pipeline.
# Tests запускаются в isolated tmpdir — production /etc/openwrt-setup-state
# не трогается.
#
# Usage: sh tests/test_state_file.sh

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INSTALL_SH=$SCRIPT_DIR/install.sh

[ -f "$INSTALL_SH" ] || { echo "FATAL: $INSTALL_SH not found" >&2; exit 1; }

pass=0
fail=0

log_pass() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
log_fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; fail=$((fail + 1)); }

# Run scenario in subshell. install.sh sourced with state-file pointed at $1.
# Caller passes shell snippet via stdin; result is exit code + last line stdout.
_run_with_state() {
    _state_file=$1
    _snippet=$2
    # SETUP_STATE_FILE — обычное присваивание в install.sh, source перезаписал
    # бы наш override. Поэтому переопределяем ПОСЛЕ source, до вызова snippet.
    INSTALL_SH_TEST_MODE=1 sh -c "
        . '$INSTALL_SH'
        SETUP_STATE_FILE='$_state_file'
        $_snippet
    " 2>&1
}

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT INT TERM

# --- state_check_done: missing file → returns 1 ---
STATE=$TMPDIR_TEST/state1
_run_with_state "$STATE" 'state_check_done step1; exit $?' >/dev/null
rc=$?
if [ "$rc" -ne 0 ]; then log_pass 'check_missing_returns_nonzero'
else log_fail 'check_missing_returns_nonzero' "expected non-zero, got $rc"; fi

# --- state_mark_done creates file + state_check_done finds key ---
STATE=$TMPDIR_TEST/state2
_run_with_state "$STATE" 'state_mark_done step1' >/dev/null
if [ -f "$STATE" ]; then log_pass 'mark_done_creates_file'
else log_fail 'mark_done_creates_file' "$STATE not created"; fi

if grep -q '^step1=done$' "$STATE" 2>/dev/null; then
    log_pass 'mark_done_writes_correct_line'
else
    log_fail 'mark_done_writes_correct_line' "expected 'step1=done' in $STATE"
fi

_run_with_state "$STATE" 'state_check_done step1; exit $?' >/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then log_pass 'check_after_mark_returns_zero'
else log_fail 'check_after_mark_returns_zero' "expected 0, got $rc"; fi

# --- mark_done idempotent (повторная запись не дублирует строку) ---
STATE=$TMPDIR_TEST/state3
_run_with_state "$STATE" 'state_mark_done step1; state_mark_done step1' >/dev/null
_count=$(grep -c '^step1=done$' "$STATE" 2>/dev/null || echo 0)
if [ "$_count" = "1" ]; then log_pass 'mark_done_idempotent'
else log_fail 'mark_done_idempotent' "expected 1 line, got $_count"; fi

# --- multiple keys coexist ---
STATE=$TMPDIR_TEST/state4
_run_with_state "$STATE" 'state_mark_done step1; state_mark_done step2; state_mark_done step3' >/dev/null
_lines=$(wc -l < "$STATE" 2>/dev/null | tr -d ' ')
if [ "$_lines" = "3" ]; then log_pass 'multiple_keys_coexist'
else log_fail 'multiple_keys_coexist' "expected 3 lines, got $_lines"; fi

_run_with_state "$STATE" 'state_check_done step2; exit $?' >/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then log_pass 'check_finds_key_among_many'
else log_fail 'check_finds_key_among_many' "expected 0, got $rc"; fi

# --- should_skip_step: skip when done AND --force-config not set ---
STATE=$TMPDIR_TEST/state5
_run_with_state "$STATE" '
    state_mark_done step1
    FLAG_FORCE_CONFIG=0
    should_skip_step step1; exit $?
' >/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then log_pass 'skip_done_step_when_force_config_off'
else log_fail 'skip_done_step_when_force_config_off' "expected 0, got $rc"; fi

# --- should_skip_step: do NOT skip when --force-config set ---
_run_with_state "$STATE" '
    state_mark_done step1
    FLAG_FORCE_CONFIG=1
    should_skip_step step1; exit $?
' >/dev/null
rc=$?
if [ "$rc" -ne 0 ]; then log_pass 'no_skip_when_force_config_on'
else log_fail 'no_skip_when_force_config_on' "expected non-zero, got $rc"; fi

# --- should_skip_step: do NOT skip step that wasn't marked ---
STATE=$TMPDIR_TEST/state6
_run_with_state "$STATE" '
    FLAG_FORCE_CONFIG=0
    should_skip_step never_marked; exit $?
' >/dev/null
rc=$?
if [ "$rc" -ne 0 ]; then log_pass 'no_skip_unmarked_step'
else log_fail 'no_skip_unmarked_step' "expected non-zero, got $rc"; fi

# --- state_clear_all удаляет файл ---
STATE=$TMPDIR_TEST/state7
_run_with_state "$STATE" 'state_mark_done step1; state_clear_all' >/dev/null
if [ ! -f "$STATE" ]; then log_pass 'clear_all_removes_file'
else log_fail 'clear_all_removes_file' "$STATE still exists"; fi

# --- state_clear_all noop когда файла нет (не должен падать) ---
STATE=$TMPDIR_TEST/state8_never_existed
_run_with_state "$STATE" 'state_clear_all; exit $?' >/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then log_pass 'clear_all_noop_when_missing'
else log_fail 'clear_all_noop_when_missing' "expected 0, got $rc"; fi

# --- mark_done не задевает другие ключи (regression: re-mark должен сохранить остальные) ---
STATE=$TMPDIR_TEST/state9
_run_with_state "$STATE" 'state_mark_done step1; state_mark_done step2; state_mark_done step1' >/dev/null
if grep -q '^step2=done$' "$STATE" 2>/dev/null; then log_pass 'remark_preserves_other_keys'
else log_fail 'remark_preserves_other_keys' "step2 disappeared after re-marking step1"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
