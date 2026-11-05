#!/usr/bin/env bash
# autocommit-pro — Interactive installer and reconfiguration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/repo"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/common.sh"
LOG_FILE="${SCRIPT_DIR}/autocommit.log"
CURRENT_PHASE="startup"
install_error_trap

info() { echo "  [INFO]  $*"; log_event INFO "${CURRENT_PHASE:-installer}" "$*"; }
ok()   { echo "  [OK]    $*"; log_event INFO "${CURRENT_PHASE:-installer}" "$*"; }
err()  { echo "  [ERROR] $*" >&2; log_event ERROR "${CURRENT_PHASE:-installer}" "$*"; }

ask_or_keep() {
    local prompt="$1" current="$2" varname="$3" answer
    if [[ -n "$current" ]]; then
        printf "  > %s [%s]: " "$prompt" "$current"
    else
        printf "  > %s: " "$prompt"
    fi
    IFS= read -r answer || { err "Input ended before configuration was complete."; exit 1; }
    if [[ -n "$answer" ]]; then
        printf -v "$varname" '%s' "$answer"
    else
        printf -v "$varname" '%s' "$current"
    fi
}

echo ""
echo "=== autocommit-pro — Installer ==="
echo ""
CURRENT_PHASE="prerequisites"
for cmd in git crontab date awk cksum mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        err "'${cmd}' is required but not found. Please install it."
        exit 1
    fi
done
ok "Prerequisites found."

FRESH_INSTALL=false
CURRENT_PHASE="configuration input"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    source "${SCRIPT_DIR}/config.sh.example"
    FRESH_INSTALL=true
fi
set_defaults

echo ""
if [[ "$FRESH_INSTALL" == false ]]; then
    info "Press Enter to keep the current value shown in [brackets]."
fi
info "GitHub requires a commit email linked to your account: https://github.com/settings/emails"
echo ""

ask_or_keep "Git user name" "${GIT_USER_NAME:-}" INPUT_GIT_NAME
ask_or_keep "Git email (must match your GitHub account)" "${GIT_USER_EMAIL:-}" INPUT_GIT_EMAIL
ask_or_keep "Min commits per run" "$MIN_COMMITS" INPUT_MIN_COMMITS
ask_or_keep "Max commits per run" "$MAX_COMMITS" INPUT_MAX_COMMITS
ask_or_keep "Frequency (daily/weekly/every2days/random)" "$FREQUENCY" INPUT_FREQUENCY
ask_or_keep "Destination (separate/self)" "$DESTINATION_MODE" INPUT_DESTINATION_MODE
AUTH_DEFAULT="${GIT_AUTH_METHOD:-}"
if [[ -z "$AUTH_DEFAULT" ]]; then
    if command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1; then
        AUTH_DEFAULT=gh
    else
        AUTH_DEFAULT=token
    fi
fi
ask_or_keep "GitHub authentication (gh/token)" "$AUTH_DEFAULT" INPUT_GIT_AUTH_METHOD

INPUT_WEEKLY_DAY="$WEEKLY_DAY"
INPUT_RANDOM_CHANCE="$RANDOM_CHANCE"
if [[ "$INPUT_FREQUENCY" == "weekly" ]]; then
    ask_or_keep "Day of week (1=Mon ... 7=Sun)" "$WEEKLY_DAY" INPUT_WEEKLY_DAY
elif [[ "$INPUT_FREQUENCY" == "random" ]]; then
    ask_or_keep "Probability (1-100)" "$RANDOM_CHANCE" INPUT_RANDOM_CHANCE
fi
ask_or_keep "Cron hour (0-23)" "$CRON_HOUR" INPUT_CRON_HOUR
ask_or_keep "Cron minute (0-59)" "$CRON_MINUTE" INPUT_CRON_MINUTE

# Validate all answers before writing configuration, creating a repo, or changing cron.
CURRENT_PHASE="configuration validation"
DESTINATION_MODE="$INPUT_DESTINATION_MODE"
GIT_AUTH_METHOD="$INPUT_GIT_AUTH_METHOD"
GIT_USER_NAME="$INPUT_GIT_NAME"
GIT_USER_EMAIL="$INPUT_GIT_EMAIL"
MIN_COMMITS="$INPUT_MIN_COMMITS"
MAX_COMMITS="$INPUT_MAX_COMMITS"
FREQUENCY="$INPUT_FREQUENCY"
WEEKLY_DAY="$INPUT_WEEKLY_DAY"
RANDOM_CHANCE="$INPUT_RANDOM_CHANCE"
CRON_HOUR="$INPUT_CRON_HOUR"
CRON_MINUTE="$INPUT_CRON_MINUTE"
GIT_REMOTE="${GIT_REMOTE:-}"
GIT_BRANCH="${GIT_BRANCH:-main}"
if [[ "$DESTINATION_MODE" == "self" ]]; then GIT_REMOTE=origin; fi
if ! validate_config installer; then exit 1; fi

CURRENT_REMOTE=""
if [[ "$DESTINATION_MODE" == "self" ]]; then
    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        err "The self destination requires a checkout of your GitHub fork."
        exit 1
    fi
    CURRENT_BRANCH=$(git -C "$SCRIPT_DIR" branch --show-current)
    if [[ -z "$CURRENT_BRANCH" ]]; then
        err "The self destination requires a checked-out branch."
        exit 1
    fi
    if ! CURRENT_REMOTE=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null); then
        err "The self destination requires an 'origin' remote pointing to your fork."
        exit 1
    fi
    GIT_BRANCH="$CURRENT_BRANCH"
    GIT_REMOTE=origin
    REMOTE_URL="$CURRENT_REMOTE"
else
    if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
        CURRENT_REMOTE=$(git -C "$REPO_DIR" remote get-url origin)
    fi
    ask_or_keep "GitHub remote URL (https://, empty to skip push)" "$CURRENT_REMOTE" REMOTE_URL
    if [[ -n "$REMOTE_URL" ]]; then
        if [[ "$REMOTE_URL" != https://* ]]; then
            err "URL must start with https:// (e.g. https://github.com/user/repo.git)."
            exit 1
        fi
        GIT_REMOTE=origin
    else
        GIT_REMOTE=""
    fi
    GIT_BRANCH="${GIT_BRANCH:-main}"
fi

if [[ "$DESTINATION_MODE" == "separate" ]]; then
    if [[ -d "$REPO_DIR/.git" ]]; then
        REPO_BRANCH=$(git -C "$REPO_DIR" branch --show-current)
    else
        REPO_BRANCH="$GIT_BRANCH"
    fi
    if [[ -n "$GIT_REMOTE" && "$REPO_BRANCH" != "$GIT_BRANCH" ]]; then
        err "repo/ is on branch '$REPO_BRANCH', but GIT_BRANCH is '$GIT_BRANCH'. Reconcile the branch before installing."
        exit 1
    fi
fi

if ! validate_config installer; then exit 1; fi
if ! git check-ref-format --branch "$GIT_BRANCH" >/dev/null 2>&1; then
    err "GIT_BRANCH is not a valid Git branch name."
    exit 1
fi

if [[ "$GIT_AUTH_METHOD" == "gh" && ( "$DESTINATION_MODE" == "self" || -n "$REMOTE_URL" ) ]]; then
    REMOTE_URL=$(strip_https_credentials "$REMOTE_URL")
    if [[ "$REMOTE_URL" != https://github.com/* ]]; then
        err "GitHub CLI authentication requires an HTTPS remote on github.com."
        exit 1
    fi
    if ! command -v gh >/dev/null 2>&1; then
        err "GitHub CLI was selected. Install gh, run 'gh auth login', and rerun install.sh."
        exit 1
    fi
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        info "Starting GitHub CLI login. Complete the browser/device flow to continue."
        if ! gh auth login --hostname github.com --git-protocol https; then
            err "GitHub CLI login did not complete. No configuration or cron changes were made."
            exit 1
        fi
    fi
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        err "GitHub CLI is not authenticated for github.com. Run 'gh auth login' and retry."
        exit 1
    fi
    if ! gh auth setup-git --force --hostname github.com >/dev/null 2>&1; then
        err "Could not configure Git to use GitHub CLI credentials."
        exit 1
    fi
    REMOTE_URL=$(strip_https_credentials "$REMOTE_URL")
    if [[ "$DESTINATION_MODE" == "self" ]]; then
        git -C "$SCRIPT_DIR" remote set-url origin "$REMOTE_URL"
    fi
fi

# Optional URL-token authentication. Read silently; gh mode never stores a token in the remote URL.
if [[ "$GIT_AUTH_METHOD" == "token" && -n "$REMOTE_URL" && "$REMOTE_URL" == https://github.com/* && "$REMOTE_URL" != *"@github.com"* ]]; then
    printf "  > Personal Access Token (leave empty for configured Git credentials): "
    IFS= read -r -s GIT_TOKEN || { err "Input ended while reading token."; exit 1; }
    printf "\n"
    if [[ -n "$GIT_TOKEN" ]]; then
        REMOTE_URL="${REMOTE_URL/https:\/\/github.com/https:\/\/x-access-token:${GIT_TOKEN}@github.com}"
    fi
fi
if [[ "$DESTINATION_MODE" == "self" && "$REMOTE_URL" != "$CURRENT_REMOTE" ]]; then
    git -C "$SCRIPT_DIR" remote set-url origin "$REMOTE_URL"
fi

# Save a complete valid configuration atomically. printf %q keeps entered values shell-safe.
CURRENT_PHASE="configuration save"
INSTALL_DIR="$SCRIPT_DIR"
if [[ -f "$CONFIG_FILE" ]]; then
    CONFIG_SOURCE="$CONFIG_FILE"
else
    CONFIG_SOURCE="${SCRIPT_DIR}/config.sh.example"
fi
write_runtime_config "$CONFIG_FILE" "$CONFIG_SOURCE" || { err "Could not write config.sh atomically."; exit 1; }
ok "Configuration saved."

if [[ "$DESTINATION_MODE" == "separate" ]]; then
    CURRENT_PHASE="repository setup"
    if [[ ! -d "$REPO_DIR/.git" ]]; then
        mkdir -p "$REPO_DIR"
        git init --quiet "$REPO_DIR"
        git -C "$REPO_DIR" checkout -b "$GIT_BRANCH" >/dev/null 2>&1
        printf '# autocommit-pro — contribution log\n' > "${REPO_DIR}/contributions.log"
        git -C "$REPO_DIR" add contributions.log
        git -C "$REPO_DIR" -c user.name="$GIT_USER_NAME" -c user.email="$GIT_USER_EMAIL" commit -m "init: autocommit-pro" --quiet
        ok "Created repo/ (branch: ${GIT_BRANCH})."
    fi
    if [[ -n "$REMOTE_URL" ]]; then
        if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
            git -C "$REPO_DIR" remote set-url origin "$REMOTE_URL"
        else
            git -C "$REPO_DIR" remote add origin "$REMOTE_URL"
        fi
        if ! git -C "$REPO_DIR" push -u origin "HEAD:refs/heads/${GIT_BRANCH}" --quiet >/dev/null 2>&1; then
            err "Initial push failed. The local commits were kept; fix the remote and run install.sh again."
            exit 1
        fi
        ok "Initial push completed."
    fi
    git -C "$REPO_DIR" config user.name "$GIT_USER_NAME"
    git -C "$REPO_DIR" config user.email "$GIT_USER_EMAIL"
else
    git -C "$SCRIPT_DIR" config user.name "$GIT_USER_NAME"
    git -C "$SCRIPT_DIR" config user.email "$GIT_USER_EMAIL"
fi

# Install cron only after configuration and repository setup succeed.
CURRENT_PHASE="cron setup"
CRON_SCRIPT="${SCRIPT_DIR}/autocommit.sh"
printf -v CRON_SCRIPT_QUOTED '%q' "$CRON_SCRIPT"
CRON_LOG="${SCRIPT_DIR}/autocommit.log"
printf -v CRON_LOG_QUOTED '%q' "$CRON_LOG"
CRON_CMD="${CRON_MINUTE} ${CRON_HOUR} * * * /usr/bin/env bash ${CRON_SCRIPT_QUOTED} >> ${CRON_LOG_QUOTED} 2>&1 # autocommit-pro"
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
FILTERED_CRON=$(printf '%s\n' "$EXISTING_CRON" | awk '!/# autocommit-pro/')
if [[ -n "$FILTERED_CRON" ]]; then
    printf '%s\n%s\n' "$FILTERED_CRON" "$CRON_CMD" | crontab -
else
    printf '%s\n' "$CRON_CMD" | crontab -
fi
ok "Cron job installed: ${CRON_CMD}"
info "Run './autocommit.sh' to run manually and 'crontab -l' to verify the schedule."
if [[ "$(uname -s)" == "Darwin" ]]; then
    info "On macOS, grant Full Disk Access to /usr/sbin/cron if scheduled runs do not start."
fi
