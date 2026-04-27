#!/bin/sh
# Fixture-based tests for preflight_release() in install.sh.
# Override OPENWRT_RELEASE_FILE+MEMINFO_FILE for filesystem fixtures; PATH-shim
# stubs apk and id so detect_pkg_manager и root-check проходят без OpenWrt.
#
# Usage: sh tests/test_preflight_release.sh

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INSTALL_SH=$SCRIPT_DIR/install.sh
FIXTURES=$SCRIPT_DIR/tests/fixtures/preflight

[ -f "$INSTALL_SH" ] || { echo "FATAL: $INSTALL_SH not found" >&2; exit 1; }
[ -d "$FIXTURES" ]   || { echo "FATAL: $FIXTURES not found" >&2; exit 1; }

pass=0
fail=0

log_pass() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
log_fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; fail=$((fail + 1)); }

# PATH-shim: apk satisfies detect_pkg_manager; id -u → 0 satisfies root check.
SHIM_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR"' EXIT INT TERM

cat > "$SHIM_DIR/apk" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$SHIM_DIR/id" <<'EOF'
#!/bin/sh
echo 0
EOF
chmod +x "$SHIM_DIR/apk" "$SHIM_DIR/id"

# _run_preflight RELEASE_FIXTURE MEMINFO_FIXTURE → exit code of preflight_release.
_run_preflight() {
    _release=$1
    _meminfo=$2
    INSTALL_SH_TEST_MODE=1 \
    OPENWRT_RELEASE_FILE="$_release" \
    MEMINFO_FILE="$_meminfo" \
    PATH="$SHIM_DIR:/usr/bin:/bin" \
    sh -c "
        . '$INSTALL_SH'
        preflight_release
    " >/dev/null 2>&1
}

# --- valid releases pass ---
_run_preflight "$FIXTURES/release/good_2410_aarch64.env" "$FIXTURES/meminfo/ok.txt"
rc=$?
if [ "$rc" -eq 0 ]; then log_pass 'valid_2410_aarch64_passes'
else log_fail 'valid_2410_aarch64_passes' "expected 0, got $rc"; fi

_run_preflight "$FIXTURES/release/good_2512_aarch64.env" "$FIXTURES/meminfo/ok.txt"
rc=$?
if [ "$rc" -eq 0 ]; then log_pass 'valid_2512_aarch64_passes'
else log_fail 'valid_2512_aarch64_passes' "expected 0, got $rc"; fi

_run_preflight "$FIXTURES/release/good_2504_mipsel.env" "$FIXTURES/meminfo/ok.txt"
rc=$?
if [ "$rc" -eq 0 ]; then log_pass 'valid_2504_mipsel_passes'
else log_fail 'valid_2504_mipsel_passes' "expected 0, got $rc"; fi

# --- unsupported release refuses (exit 2) ---
_run_preflight "$FIXTURES/release/unsupported_release.env" "$FIXTURES/meminfo/ok.txt"
rc=$?
if [ "$rc" -eq 2 ]; then log_pass 'unsupported_release_refuses'
else log_fail 'unsupported_release_refuses' "expected exit 2, got $rc"; fi

# --- unsupported architecture refuses (exit 2) ---
_run_preflight "$FIXTURES/release/bad_arch.env" "$FIXTURES/meminfo/ok.txt"
rc=$?
if [ "$rc" -eq 2 ]; then log_pass 'bad_arch_refuses'
else log_fail 'bad_arch_refuses' "expected exit 2, got $rc"; fi

# --- low RAM refuses (exit 2) ---
_run_preflight "$FIXTURES/release/good_2512_aarch64.env" "$FIXTURES/meminfo/low.txt"
rc=$?
if [ "$rc" -eq 2 ]; then log_pass 'low_ram_refuses'
else log_fail 'low_ram_refuses' "expected exit 2, got $rc"; fi

# --- missing release file refuses (exit 2) ---
_run_preflight "$FIXTURES/release/does_not_exist.env" "$FIXTURES/meminfo/ok.txt"
rc=$?
if [ "$rc" -eq 2 ]; then log_pass 'missing_release_file_refuses'
else log_fail 'missing_release_file_refuses' "expected exit 2, got $rc"; fi

# --- env-override: SUPPORTED_RELEASES расширяется через env (regression) ---
INSTALL_SH_TEST_MODE=1 \
SUPPORTED_RELEASES='99.99.99' \
OPENWRT_RELEASE_FILE="$FIXTURES/release/unsupported_release.env" \
MEMINFO_FILE="$FIXTURES/meminfo/ok.txt" \
PATH="$SHIM_DIR:/usr/bin:/bin" \
sh -c "
    . '$INSTALL_SH'
    # 23.05.0 не в env-override '99.99.99' → должен refuse
    preflight_release
" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then log_pass 'env_supported_releases_override_honored'
else log_fail 'env_supported_releases_override_honored' "expected 2, got $rc"; fi

# --- detected globals populated после успешного passing ---
_dump=$(INSTALL_SH_TEST_MODE=1 \
    OPENWRT_RELEASE_FILE="$FIXTURES/release/good_2512_aarch64.env" \
    MEMINFO_FILE="$FIXTURES/meminfo/ok.txt" \
    PATH="$SHIM_DIR:/usr/bin:/bin" \
    sh -c "
        . '$INSTALL_SH'
        preflight_release >/dev/null 2>&1
        printf 'DETECTED_RELEASE=%s\n' \"\$DETECTED_RELEASE\"
        printf 'DETECTED_ARCH=%s\n'    \"\$DETECTED_ARCH\"
        printf 'PKG_MANAGER=%s\n'      \"\$PKG_MANAGER\"
    " 2>/dev/null)

if printf '%s\n' "$_dump" | grep -Fxq 'DETECTED_RELEASE=25.12.2'; then
    log_pass 'detected_release_populated'
else
    log_fail 'detected_release_populated' "missing DETECTED_RELEASE=25.12.2 in: $_dump"
fi

if printf '%s\n' "$_dump" | grep -Fxq 'DETECTED_ARCH=aarch64_cortex-a53'; then
    log_pass 'detected_arch_populated'
else
    log_fail 'detected_arch_populated' "missing DETECTED_ARCH in: $_dump"
fi

if printf '%s\n' "$_dump" | grep -Fxq 'PKG_MANAGER=apk'; then
    log_pass 'pkg_manager_detected_apk_via_shim'
else
    log_fail 'pkg_manager_detected_apk_via_shim' "missing PKG_MANAGER=apk in: $_dump"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
