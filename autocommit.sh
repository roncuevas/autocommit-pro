#!/usr/bin/env bash
# autocommit-pro — Main Script
# Generates automatic commits to fill the GitHub contribution graph.

set -euo pipefail

# Ensure git is reachable from cron on macOS
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

# ── Resolve script directory ──────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
LOG_FILE="${SCRIPT_DIR}/autocommit.log"
REPO_DIR="${SCRIPT_DIR}/repo"
DATA_FILE="${REPO_DIR}/contributions.log"

# ── Load configuration ────────────────────────────────────────
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: config.sh not found. Run install.sh first." | tee -a "$LOG_FILE"
    exit 1
fi
# shellcheck source=config.sh.example
source "$CONFIG_FILE"

# ── Logging helper ────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# ── Verify repo directory ────────────────────────────────────
if [[ ! -d "$REPO_DIR/.git" ]]; then
    log "ERROR: repo/ directory not initialized. Run install.sh first."
    exit 1
fi

# ── Frequency gate ────────────────────────────────────────────
should_run_today() {
    case "$FREQUENCY" in
        daily)
            return 0
            ;;
        weekly)
            local today
            today=$(date +%u)
            [[ "$today" -eq "$WEEKLY_DAY" ]]
            return $?
            ;;
        every2days)
            local epoch_day
            epoch_day=$(( $(date +%s) / 86400 ))
            [[ $(( epoch_day % 2 )) -eq 0 ]]
            return $?
            ;;
        random)
            local roll
            roll=$(( RANDOM % 100 + 1 ))
            [[ "$roll" -le "$RANDOM_CHANCE" ]]
            return $?
            ;;
        *)
            log "ERROR: Unknown FREQUENCY '${FREQUENCY}'"
            return 1
            ;;
    esac
}

if ! should_run_today; then
    log "SKIP: Frequency gate (${FREQUENCY}) — not running today."
    exit 0
fi

# ── Calculate number of commits ───────────────────────────────
NUM_COMMITS=$(( RANDOM % (MAX_COMMITS - MIN_COMMITS + 1) + MIN_COMMITS ))
log "START: Will create ${NUM_COMMITS} commit(s)."

# ── Configure git identity ──────────────────────────────────
if [[ -z "${GIT_USER_NAME:-}" || -z "${GIT_USER_EMAIL:-}" ]]; then
    log "ERROR: GIT_USER_NAME and GIT_USER_EMAIL must be set in config.sh"
    exit 1
fi

# ── Perform commits ──────────────────────────────────────────
cd "$REPO_DIR"
git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

for (( i = 1; i <= NUM_COMMITS; i++ )); do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${TIMESTAMP} — autocommit #${i}/${NUM_COMMITS}" >> "$DATA_FILE"
    git add contributions.log
    git commit -m "autocommit: ${TIMESTAMP}" --quiet
    log "COMMIT ${i}/${NUM_COMMITS}: autocommit: ${TIMESTAMP}"
done

# ── Push to remote (if configured) ───────────────────────────
if [[ -n "${GIT_REMOTE:-}" ]]; then
    # Pull remote changes first to avoid rejection
    git pull --rebase "$GIT_REMOTE" "$GIT_BRANCH" --quiet 2>>"$LOG_FILE" || true
    if git push "$GIT_REMOTE" "$GIT_BRANCH" --quiet 2>>"$LOG_FILE"; then
        log "PUSH: Success to ${GIT_REMOTE}/${GIT_BRANCH}"
    else
        log "PUSH: FAILED to ${GIT_REMOTE}/${GIT_BRANCH}"
    fi
fi

log "DONE: ${NUM_COMMITS} commit(s) created."
