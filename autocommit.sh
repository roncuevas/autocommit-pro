#!/usr/bin/env bash
# autocommit-pro — Main scheduled/manual run.

set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/autocommit.log}"
REPO_DIR="${SCRIPT_DIR}/repo"
CURRENT_PHASE="startup"
source "${SCRIPT_DIR}/common.sh"
install_error_trap

log() {
    log_event INFO "${CURRENT_PHASE:-run}" "$*"
}
fail() { log_event ERROR "${CURRENT_PHASE:-run}" "$*"; printf 'autocommit-pro: %s\n' "$*" >&2; exit 1; }

if [[ ! -f "$CONFIG_FILE" ]]; then
    fail "config.sh not found. Run install.sh first."
fi
source "$CONFIG_FILE"
set_defaults
CURRENT_PHASE="configuration"
if ! validate_config runtime; then
    fail "Invalid configuration. Correct config.sh before retrying."
fi

case "$DESTINATION_MODE" in
    separate) DATA_FILE="${REPO_DIR}/contributions.log" ;;
    self) REPO_DIR="$SCRIPT_DIR"; DATA_FILE="${REPO_DIR}/CHANGELOG.md" ;;
esac

CURRENT_PHASE="repository validation"
if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    fail "Destination repository is not initialized. Run install.sh first."
fi
if ! git check-ref-format --branch "$GIT_BRANCH" >/dev/null 2>&1; then
    fail "GIT_BRANCH is not a valid Git branch name."
fi

should_run_today() {
    case "$FREQUENCY" in
        daily) return 0 ;;
        weekly) [[ "$(date +%u)" -eq "$WEEKLY_DAY" ]] ;;
        every2days) [[ $(( $(date +%s) / 86400 % 2 )) -eq 0 ]] ;;
        random) [[ $(( RANDOM % 100 + 1 )) -le "$RANDOM_CHANCE" ]] ;;
    esac
}

if ! should_run_today; then
    log "SKIP: Frequency gate (${FREQUENCY}) — not running today."
    exit 0
fi

if [[ "$DESTINATION_MODE" == "self" || -n "$GIT_REMOTE" ]]; then
    git -C "$REPO_DIR" remote get-url "$GIT_REMOTE" >/dev/null 2>&1 || fail "Git remote '${GIT_REMOTE}' is not configured."
    CURRENT_BRANCH=$(git -C "$REPO_DIR" branch --show-current)
    [[ "$CURRENT_BRANCH" == "$GIT_BRANCH" ]] || fail "Checkout branch '${CURRENT_BRANCH}' does not match GIT_BRANCH '${GIT_BRANCH}'."
fi

acquire_autocommit_lock "$REPO_DIR" || fail "Another run is active, or a stale lock must be removed."

CURRENT_PHASE="worktree validation"
if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
    fail "Destination has local changes. Commit or stash them before running."
fi

if [[ -z "$GIT_USER_NAME" || -z "$GIT_USER_EMAIL" ]]; then
    fail "GIT_USER_NAME and GIT_USER_EMAIL must be set in config.sh."
fi

cd "$REPO_DIR"
git config user.name "$GIT_USER_NAME" || fail "Could not configure the Git commit author name."
git config user.email "$GIT_USER_EMAIL" || fail "Could not configure the Git commit author email."

# Synchronize before writing. On failure, abort an in-progress rebase and keep existing commits.
CURRENT_PHASE="remote synchronization"
if [[ -n "$GIT_REMOTE" ]]; then
    if ! git pull --rebase "$GIT_REMOTE" "$GIT_BRANCH" --quiet >/dev/null 2>&1; then
        git rebase --abort >/dev/null 2>&1 || true
        fail "Could not rebase onto ${GIT_REMOTE}/${GIT_BRANCH}; no new commits were created."
    fi
fi

NUM_COMMITS=$(( RANDOM % (MAX_COMMITS - MIN_COMMITS + 1) + MIN_COMMITS ))
CURRENT_PHASE="commit creation"
log "START: Will create ${NUM_COMMITS} commit(s) in ${DESTINATION_MODE} mode."
if [[ "$DESTINATION_MODE" == "self" && ! -f "$DATA_FILE" ]]; then
    printf '# Changelog\n\n' > "$DATA_FILE" || fail "Could not create CHANGELOG.md."
fi

for (( i = 1; i <= NUM_COMMITS; i++ )); do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    if [[ "$DESTINATION_MODE" == "self" ]]; then
        printf -- '- %s — autocommit #%s/%s\n' "$TIMESTAMP" "$i" "$NUM_COMMITS" >> "$DATA_FILE" || fail "Could not update CHANGELOG.md; local changes were preserved."
        git add CHANGELOG.md || fail "Could not stage CHANGELOG.md; local changes were preserved."
    else
        printf '%s — autocommit #%s/%s\n' "$TIMESTAMP" "$i" "$NUM_COMMITS" >> "$DATA_FILE" || fail "Could not update contributions.log; local changes were preserved."
        git add contributions.log || fail "Could not stage contributions.log; local changes were preserved."
    fi
    if ! git commit -m "autocommit: ${TIMESTAMP} (${i}/${NUM_COMMITS})" --quiet; then
        fail "Commit ${i}/${NUM_COMMITS} failed; local changes were preserved for recovery."
    fi
    log "COMMIT ${i}/${NUM_COMMITS}: autocommit: ${TIMESTAMP}"
done

CURRENT_PHASE="push"
if [[ -n "$GIT_REMOTE" ]]; then
    if ! git push "$GIT_REMOTE" "HEAD:refs/heads/${GIT_BRANCH}" --quiet >/dev/null 2>&1; then
        fail "Push failed. Local commits were kept and will be retried on a later run."
    fi
    log "PUSH: Success to ${GIT_REMOTE}/${GIT_BRANCH}"
fi

log "DONE: ${NUM_COMMITS} commit(s) created."
