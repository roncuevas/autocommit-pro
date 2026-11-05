#!/usr/bin/env bash
# Docker bootstrap for both persistent destination modes.

set -euo pipefail

IMAGE_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$IMAGE_DIR"
source "${IMAGE_DIR}/common.sh"
LOG_FILE="${LOG_FILE:-/logs/autocommit.log}"
LOG_STDOUT=1
export LOG_FILE LOG_STDOUT
mkdir -p "$(dirname "$LOG_FILE")"
CURRENT_PHASE="startup"
install_error_trap

info() { echo "  [INFO]  $*"; log_event INFO "${CURRENT_PHASE:-bootstrap}" "$*"; }
ok()   { echo "  [OK]    $*"; log_event INFO "${CURRENT_PHASE:-bootstrap}" "$*"; }
err()  { echo "  [ERROR] $*" >&2; log_event ERROR "${CURRENT_PHASE:-bootstrap}" "$*"; }

DESTINATION_MODE="${DESTINATION_MODE:-separate}"
GIT_AUTH_METHOD="${GIT_AUTH_METHOD:-token}"
MIN_COMMITS="${MIN_COMMITS:-1}"
MAX_COMMITS="${MAX_COMMITS:-5}"
FREQUENCY="${FREQUENCY:-daily}"
WEEKLY_DAY="${WEEKLY_DAY:-1}"
RANDOM_CHANCE="${RANDOM_CHANCE:-50}"
CRON_HOUR="${CRON_HOUR:-9}"
CRON_MINUTE="${CRON_MINUTE:-30}"
GIT_USER_NAME="${GIT_USER_NAME:-}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"
GIT_REMOTE=origin
GIT_BRANCH="${GIT_BRANCH:-main}"

if [[ -z "${REMOTE_URL:-}" || "$REMOTE_URL" != https://* ]]; then
    err "REMOTE_URL is required and must start with https://."
    exit 1
fi
if ! validate_config installer; then exit 1; fi
if ! git check-ref-format --branch "$GIT_BRANCH" >/dev/null 2>&1; then
    err "GIT_BRANCH is not a valid Git branch name."
    exit 1
fi

if [[ "$GIT_AUTH_METHOD" == "gh" ]]; then
    CURRENT_PHASE="GitHub authentication"
    REMOTE_URL=$(strip_https_credentials "$REMOTE_URL")
    if [[ "$REMOTE_URL" != https://github.com/* ]]; then
        err "GitHub CLI authentication requires an HTTPS remote on github.com."
        exit 1
    fi
    if [[ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]]; then
        err "Docker uses non-interactive authentication. Export GH_TOKEN or GITHUB_TOKEN before starting the container."
        exit 1
    fi
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        err "GitHub CLI could not authenticate with GH_TOKEN/GITHUB_TOKEN. Check token access and expiration."
        exit 1
    fi
    if ! gh auth setup-git --force --hostname github.com >/dev/null 2>&1; then
        err "GitHub CLI could not configure Git credential access."
        exit 1
    fi
fi

echo ""
echo "=== autocommit-pro — Docker Setup ==="
echo ""

if [[ "$DESTINATION_MODE" == "self" ]]; then
    CURRENT_PHASE="self destination bootstrap"
    DATA_DIR="${DATA_DIR:-/data}"
    APP_DIR="${DATA_DIR}/autocommit-pro"
    mkdir -p "$DATA_DIR"
    if [[ ! -d "${APP_DIR}/.git" ]]; then
        if [[ -n "$(ls -A "$APP_DIR" 2>/dev/null || true)" ]]; then
            err "${APP_DIR} is not empty and is not a Git checkout. Move or back up its contents before retrying."
            exit 1
        fi
        mkdir -p "$APP_DIR"
        CLONE_ERROR="${DATA_DIR}/clone-error.log"
        if ! git clone --quiet --branch "$GIT_BRANCH" "$REMOTE_URL" "$APP_DIR" 2> "$CLONE_ERROR"; then
            rm -rf "$APP_DIR"
            rm -f "$CLONE_ERROR"
            err "Could not clone the self destination. Check REMOTE_URL, branch, credentials, and the persistent volume."
            exit 1
        fi
        rm -f "$CLONE_ERROR"
        ok "Cloned the fork into the persistent data volume."
    fi
    REPO_DIR="$APP_DIR"
    SCRIPT_DIR="$APP_DIR"
    if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        err "Persistent self destination is not a valid Git checkout."
        exit 1
    fi
    CURRENT_BRANCH=$(git -C "$REPO_DIR" branch --show-current)
    if [[ "$CURRENT_BRANCH" != "$GIT_BRANCH" ]]; then
        err "Persistent checkout is on '$CURRENT_BRANCH', expected '$GIT_BRANCH'."
        exit 1
    fi
    git -C "$REPO_DIR" remote set-url origin "$REMOTE_URL"
else
    CURRENT_PHASE="separate destination bootstrap"
    REPO_DIR="${IMAGE_DIR}/repo"
    mkdir -p "$REPO_DIR"
    if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git init --quiet "$REPO_DIR"
        git -C "$REPO_DIR" checkout -b "$GIT_BRANCH" >/dev/null 2>&1
        printf '# autocommit-pro — contribution log\n' > "${REPO_DIR}/contributions.log"
        git -C "$REPO_DIR" add contributions.log
        git -C "$REPO_DIR" -c user.name="$GIT_USER_NAME" -c user.email="$GIT_USER_EMAIL" commit -m "init: autocommit-pro" --quiet
    fi
    CURRENT_BRANCH=$(git -C "$REPO_DIR" branch --show-current)
    if [[ "$CURRENT_BRANCH" != "$GIT_BRANCH" ]]; then
        err "Persistent repo/ is on '$CURRENT_BRANCH', expected '$GIT_BRANCH'."
        exit 1
    fi
    if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
        git -C "$REPO_DIR" remote set-url origin "$REMOTE_URL"
    else
        git -C "$REPO_DIR" remote add origin "$REMOTE_URL"
    fi
fi

GIT_REMOTE=origin
INSTALL_DIR="$SCRIPT_DIR"
CURRENT_PHASE="runtime configuration"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
write_runtime_config "$CONFIG_FILE" "${SCRIPT_DIR}/config.sh.example" || { err "Could not write runtime configuration."; exit 1; }
git -C "$REPO_DIR" config user.name "$GIT_USER_NAME"
git -C "$REPO_DIR" config user.email "$GIT_USER_EMAIL"

# Only a newly initialized separate repo needs an initial push. Never force-push.
CURRENT_PHASE="initial push"
if [[ "$DESTINATION_MODE" == "separate" ]] && ! git -C "$REPO_DIR" rev-parse --verify "refs/remotes/origin/${GIT_BRANCH}" >/dev/null 2>&1; then
    if ! git -C "$REPO_DIR" push -u origin "HEAD:refs/heads/${GIT_BRANCH}" --quiet >/dev/null 2>&1; then
        err "Initial push failed. The persistent local commits were kept; correct the remote and restart."
        exit 1
    fi
fi

CRON_SCRIPT="${SCRIPT_DIR}/autocommit.sh"
printf -v CRON_SCRIPT_QUOTED '%q' "$CRON_SCRIPT"
CRON_CMD="${CRON_MINUTE} ${CRON_HOUR} * * * /usr/bin/env bash ${CRON_SCRIPT_QUOTED} >> /proc/1/fd/1 2>&1 # autocommit-pro"
CURRENT_PHASE="cron setup"
printf '%s\n' "$CRON_CMD" | crontab -
ok "Cron job installed for ${DESTINATION_MODE} destination."
info "Frequency: ${FREQUENCY}; commits per run: ${MIN_COMMITS}–${MAX_COMMITS}; timezone: ${TZ:-UTC}."
exec crond -f -l 2
