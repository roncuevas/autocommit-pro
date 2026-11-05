#!/usr/bin/env bash
# Unit tests for shared validation, credential handling, config writing, and logging.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/autocommit-pro-unit.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
source "$ROOT/common.sh"
PASS=0

pass() { PASS=$((PASS + 1)); printf 'ok unit %s - %s\n' "$PASS" "$1"; }
fail() { printf 'not ok unit - %s\n' "$1" >&2; exit 1; }

[[ "$(normalize_uint 00042)" == 42 ]] || fail "leading zero normalization"
pass "normalizes bounded unsigned integers"
if normalize_uint 2147483648 >/dev/null 2>&1; then fail "integer overflow accepted"; fi
if normalize_uint 1x >/dev/null 2>&1; then fail "non-numeric value accepted"; fi
pass "rejects malformed and overflowing integers"

[[ "$(strip_https_credentials 'https://x-access-token:secret@github.com/user/repo.git')" == 'https://github.com/user/repo.git' ]] || fail "HTTPS credentials not stripped"
[[ "$(strip_https_credentials 'https://github.com/user/repo.git')" == 'https://github.com/user/repo.git' ]] || fail "credential-free URL changed"
pass "strips HTTPS user information without changing the repository path"

DESTINATION_MODE=separate MIN_COMMITS=01 MAX_COMMITS=03 FREQUENCY=weekly WEEKLY_DAY=07 RANDOM_CHANCE=50 CRON_HOUR=09 CRON_MINUTE=05 GIT_USER_NAME=Tester GIT_USER_EMAIL=test@example.invalid GIT_REMOTE='' GIT_BRANCH=main GIT_AUTH_METHOD=gh
set_defaults
validate_config installer >/dev/null || fail "valid installer configuration rejected"
[[ "$MIN_COMMITS" == 1 && "$MAX_COMMITS" == 3 && "$WEEKLY_DAY" == 7 && "$CRON_HOUR" == 9 && "$CRON_MINUTE" == 5 ]] || fail "validated values not normalized"
pass "validates and normalizes configuration values"

if (DESTINATION_MODE=self MIN_COMMITS=1 MAX_COMMITS=1 FREQUENCY=daily GIT_USER_NAME=Tester GIT_USER_EMAIL=test@example.invalid GIT_REMOTE='' GIT_BRANCH=main GIT_AUTH_METHOD=gh; set_defaults; validate_config runtime >/dev/null 2>&1); then
    fail "self destination without remote accepted"
fi
if (DESTINATION_MODE=separate MIN_COMMITS=1 MAX_COMMITS=2 FREQUENCY=daily GIT_USER_NAME=$'bad\nname' GIT_USER_EMAIL=test@example.invalid GIT_REMOTE='' GIT_BRANCH=main GIT_AUTH_METHOD=token; set_defaults; validate_config runtime >/dev/null 2>&1); then
    fail "multiline Git identity accepted"
fi
pass "rejects incomplete publishing and multiline identity settings"

CONFIG="$TMP_ROOT/config.sh"
printf '# custom\nCUSTOM_SETTING=kept\nMIN_COMMITS=999\n' > "$CONFIG"
INSTALL_DIR="$TMP_ROOT"
write_runtime_config "$CONFIG" "$CONFIG" || fail "atomic config write failed"
(source "$CONFIG"; [[ "$CUSTOM_SETTING" == kept && "$MIN_COMMITS" == 1 && "$GIT_AUTH_METHOD" == gh ]]) || fail "config round-trip mismatch"
pass "rewrites config atomically while preserving user settings"

LOG_FILE="$TMP_ROOT/autocommit.log"
CURRENT_PHASE="unit"
log_event ERROR "$CURRENT_PHASE" "safe diagnostic"
grep -q '\[ERROR\] \[unit\] safe diagnostic' "$LOG_FILE" || fail "structured log entry missing"
pass "writes timestamped, leveled, phase-aware diagnostics"

UNEXPECTED_LOG="$TMP_ROOT/unexpected.log"
cat > "$TMP_ROOT/unexpected.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$ROOT/common.sh"
LOG_FILE="$UNEXPECTED_LOG"
CURRENT_PHASE="test phase"
install_error_trap
false
EOF
if bash "$TMP_ROOT/unexpected.sh" >/dev/null 2>&1; then
    fail "unexpected failure escaped the error trap"
fi
grep -q '\[ERROR\] \[test phase\] Unexpected command failure (exit 1)' "$UNEXPECTED_LOG" || fail "unexpected failure was not logged"
pass "logs unexpected failures with phase and exit status"

printf '1..%s\n' "$PASS"
