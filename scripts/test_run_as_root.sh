#!/bin/bash
# ============================================================
# test_run_as_root.sh
# ------------------------------------------------------------
# Harness to validate run_as_root behavior with assertions
# ============================================================

set -euo pipefail
source "${HOME}/src/homelab/scripts/common.sh"

fail() {
    log "❌ Test failed: $1"
    exit 1
}

pass() {
    log "✅ Test passed: $1"
}

log "=== Test 1: simple command ==="
output=$(run_as_root echo "Hello from run_as_root")
[[ "$output" == "Hello from run_as_root" ]] || fail "simple command"
pass "simple command"

log "=== Test 2: command with spaces in args ==="
touch "/tmp/file with spaces.txt"
output=$(run_as_root ls "/tmp/file with spaces.txt")
[[ "$output" == *"file with spaces.txt"* ]] || fail "spaces in args"
pass "spaces in args"

log "=== Test 3: chained commands ==="
output=$(run_as_root "echo First && echo Second")
[[ "$output" == *"First"* && "$output" == *"Second"* ]] || fail "chained commands"
pass "chained commands"

log "=== Test 4: env assignment ==="
output=$(run_as_root "bash -c 'FOO=bar; echo \$FOO'")
[[ "$output" == "bar" ]] || fail "env assignment"
pass "env assignment"

log "=== Test 5: inherited env (expected empty) ==="
FOO=bar
output=$(run_as_root bash -c 'echo ${FOO:-unset}')
[[ "$output" == "unset" ]] || fail "env isolation"
pass "env isolation"

log "=== Test 6: simple command with --preserve ==="
output=$(run_as_root --preserve echo "Hello from preserve")
[[ "$output" == "Hello from preserve" ]] || fail "simple command preserve"
pass "simple command preserve"

log "=== Test 7: command with spaces in args (preserve) ==="
touch "/tmp/preserve file.txt"
output=$(run_as_root --preserve "ls '/tmp/preserve file.txt'")
[[ "$output" == *"preserve file.txt"* ]] || fail "spaces in args preserve"
pass "spaces in args preserve"

log "=== Test 8: chained commands (preserve) ==="
output=$(run_as_root --preserve "echo FirstPreserve && echo SecondPreserve")
[[ "$output" == *"FirstPreserve"* && "$output" == *"SecondPreserve"* ]] || fail "chained commands preserve"
pass "chained commands preserve"

log "=== Test 9: env assignment (preserve) ==="
output=$(run_as_root --preserve "bash -c 'FOO=bar; echo \$FOO'")
[[ "$output" == "bar" ]] || fail "env assignment preserve"
pass "env assignment preserve"

log "=== Test 10: inherited env (preserve) ==="
export FOO=bar
output=$(run_as_root --preserve "bash -c 'echo \$FOO'")
[[ "$output" == "bar" ]] || fail "inherited env preserve"
pass "inherited env preserve"

log "All run_as_root tests passed 🎉"
