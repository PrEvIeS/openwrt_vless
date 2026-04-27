#!/bin/sh
# Unit tests for _get_agh_bind_port() in install.sh.
#
# Гарантирует что configure_adguard сохраняет операторский AGH bind_port
# через --force-config (см. beads openwrt_script-3co).
#
# Usage: sh tests/test_agh_bind_port.sh

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INSTALL_SH=$SCRIPT_DIR/install.sh

[ -f "$INSTALL_SH" ] || { echo "FATAL: $INSTALL_SH not found" >&2; exit 1; }

pass=0
fail=0

log_pass() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
log_fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; fail=$((fail + 1)); }

# Read existing AGH yaml fixture, expect specific port (or empty).
_check() {
    name=$1
    fixture=$2
    expected=$3

    actual=$(INSTALL_SH_TEST_MODE=1 sh -c "
        . '$INSTALL_SH'
        _get_agh_bind_port '$fixture'
    " 2>/dev/null)

    if [ "$actual" = "$expected" ]; then
        log_pass "$name"
    else
        log_fail "$name" "expected='$expected' got='$actual'"
    fi
}

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT INT TERM

# --- Fixtures ---

# Default fresh install — bind_port: 3000.
cat > "$TMPDIR_TEST/default.yaml" <<'EOF'
bind_host: 0.0.0.0
bind_port: 3000
users: []
EOF

# Operator moved admin to :8080 via wizard.
cat > "$TMPDIR_TEST/custom.yaml" <<'EOF'
bind_host: 0.0.0.0
bind_port: 8080
users: []
dns:
  port: 53
EOF

# bind_port lives below dns: section — first match wins, must catch top-level.
cat > "$TMPDIR_TEST/nested.yaml" <<'EOF'
bind_host: 0.0.0.0
bind_port: 9999
dns:
  bind_port: 53
EOF

# Non-numeric port (corrupt yaml).
cat > "$TMPDIR_TEST/garbage.yaml" <<'EOF'
bind_host: 0.0.0.0
bind_port: notanumber
EOF

# Empty bind_port value.
cat > "$TMPDIR_TEST/empty.yaml" <<'EOF'
bind_host: 0.0.0.0
bind_port:
EOF

# bind_port absent.
cat > "$TMPDIR_TEST/missing.yaml" <<'EOF'
bind_host: 0.0.0.0
users: []
EOF

# --- Tests ---

echo "_get_agh_bind_port:"
_check "default 3000"           "$TMPDIR_TEST/default.yaml" "3000"
_check "custom 8080 preserved"  "$TMPDIR_TEST/custom.yaml"  "8080"
_check "first match wins"       "$TMPDIR_TEST/nested.yaml"  "9999"
_check "garbage rejected"       "$TMPDIR_TEST/garbage.yaml" ""
_check "empty value rejected"   "$TMPDIR_TEST/empty.yaml"   ""
_check "missing field"          "$TMPDIR_TEST/missing.yaml" ""
_check "nonexistent file"       "$TMPDIR_TEST/does-not-exist.yaml" ""

echo
echo "Pass: $pass  Fail: $fail"
[ "$fail" -eq 0 ]
