#!/usr/bin/env bash
# autocommit-pro — Installer
# Sets up the config, contribution repo, and cron job.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/repo"

# ── Helpers ───────────────────────────────────────────────────
info()  { echo "  [INFO]  $*"; }
ok()    { echo "  [OK]    $*"; }
err()   { echo "  [ERROR] $*" >&2; }
ask()   { printf "  > %s " "$*"; }

sed_inplace() {
    # Cross-platform sed -i
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Prompt for a value, showing current default. Enter keeps current value.
ask_or_keep() {
    local prompt="$1" current="$2" varname="$3"
    if [[ -n "$current" ]]; then
        printf "  > %s [%s]: " "$prompt" "$current"
    else
        printf "  > %s: " "$prompt"
    fi
    read -r INPUT
    if [[ -n "$INPUT" ]]; then
        eval "$varname='$INPUT'"
    else
        eval "$varname='$current'"
    fi
}

# ── Prerequisites ─────────────────────────────────────────────
echo ""
echo "=== autocommit-pro — Installer ==="
echo ""

for cmd in git crontab date; do
    if ! command -v "$cmd" &>/dev/null; then
        err "'${cmd}' is required but not found. Please install it."
        exit 1
    fi
done
ok "Prerequisites found (git, crontab, date)."

# ── Config file ───────────────────────────────────────────────
cd "$SCRIPT_DIR"

FRESH_INSTALL=false
if [[ ! -f config.sh ]]; then
    cp config.sh.example config.sh
    sed_inplace "s|^INSTALL_DIR=.*|INSTALL_DIR=\"${SCRIPT_DIR}\"|" config.sh
    ok "Created config.sh from template."
    FRESH_INSTALL=true
else
    ok "config.sh found — loading current values."
fi

# Source config for current values
source config.sh

# ── Interactive configuration ────────────────────────────────
echo ""
if [[ "$FRESH_INSTALL" == false ]]; then
    info "Press Enter to keep the current value shown in [brackets]."
fi
info "GitHub requires commits to use an email linked to your account."
info "Find your email at: https://github.com/settings/emails"
echo ""

# Git identity
ask_or_keep "Git user name" "${GIT_USER_NAME:-}" INPUT_GIT_NAME
if [[ -z "$INPUT_GIT_NAME" ]]; then
    err "Git user name is required for GitHub to recognize your contributions."
    exit 1
fi

ask_or_keep "Git email (must match your GitHub account)" "${GIT_USER_EMAIL:-}" INPUT_GIT_EMAIL
if [[ -z "$INPUT_GIT_EMAIL" ]]; then
    err "Git email is required for GitHub to recognize your contributions."
    exit 1
fi

# Commit range
ask_or_keep "Min commits per run" "${MIN_COMMITS:-1}" INPUT_MIN_COMMITS
ask_or_keep "Max commits per run" "${MAX_COMMITS:-5}" INPUT_MAX_COMMITS

# Frequency
ask_or_keep "Frequency (daily/weekly/every2days/random)" "${FREQUENCY:-daily}" INPUT_FREQUENCY

INPUT_WEEKLY_DAY="${WEEKLY_DAY:-1}"
INPUT_RANDOM_CHANCE="${RANDOM_CHANCE:-50}"
if [[ "$INPUT_FREQUENCY" == "weekly" ]]; then
    ask_or_keep "Day of week (1=Mon ... 7=Sun)" "${WEEKLY_DAY:-1}" INPUT_WEEKLY_DAY
elif [[ "$INPUT_FREQUENCY" == "random" ]]; then
    ask_or_keep "Probability 1-100" "${RANDOM_CHANCE:-50}" INPUT_RANDOM_CHANCE
fi

# Cron schedule
ask_or_keep "Cron hour (0-23)" "${CRON_HOUR:-9}" INPUT_CRON_HOUR
ask_or_keep "Cron minute (0-59)" "${CRON_MINUTE:-30}" INPUT_CRON_MINUTE

# Write all values to config.sh
sed_inplace "s|^GIT_USER_NAME=.*|GIT_USER_NAME=\"${INPUT_GIT_NAME}\"|" config.sh
sed_inplace "s|^GIT_USER_EMAIL=.*|GIT_USER_EMAIL=\"${INPUT_GIT_EMAIL}\"|" config.sh
sed_inplace "s|^MIN_COMMITS=.*|MIN_COMMITS=${INPUT_MIN_COMMITS}|" config.sh
sed_inplace "s|^MAX_COMMITS=.*|MAX_COMMITS=${INPUT_MAX_COMMITS}|" config.sh
sed_inplace "s|^FREQUENCY=.*|FREQUENCY=\"${INPUT_FREQUENCY}\"|" config.sh
sed_inplace "s|^WEEKLY_DAY=.*|WEEKLY_DAY=${INPUT_WEEKLY_DAY}|" config.sh
sed_inplace "s|^RANDOM_CHANCE=.*|RANDOM_CHANCE=${INPUT_RANDOM_CHANCE}|" config.sh
sed_inplace "s|^CRON_HOUR=.*|CRON_HOUR=${INPUT_CRON_HOUR}|" config.sh
sed_inplace "s|^CRON_MINUTE=.*|CRON_MINUTE=${INPUT_CRON_MINUTE}|" config.sh
ok "Configuration saved."

# Reload config with new values
source config.sh

# ── Contribution repo (separate from autocommit-pro) ─────────
if [[ ! -d "$REPO_DIR/.git" ]]; then
    mkdir -p "$REPO_DIR"
    git init --quiet "$REPO_DIR"
    echo "# autocommit-pro — contribution log" > "$REPO_DIR/contributions.log"
    git -C "$REPO_DIR" add contributions.log
    git -C "$REPO_DIR" commit -m "init: autocommit-pro" --quiet
    git -C "$REPO_DIR" branch -M main
    ok "Created repo/ with clean git history (branch: main)."
else
    info "repo/ already initialized — updating git identity."
fi
git -C "$REPO_DIR" config user.name "$INPUT_GIT_NAME"
git -C "$REPO_DIR" config user.email "$INPUT_GIT_EMAIL"

# ── Remote setup (optional) ──────────────────────────────────
echo ""
CURRENT_REMOTE=""
if git -C "$REPO_DIR" remote get-url origin &>/dev/null; then
    CURRENT_REMOTE=$(git -C "$REPO_DIR" remote get-url origin)
fi

ask_or_keep "GitHub remote URL (https://)" "$CURRENT_REMOTE" REMOTE_URL

if [[ -n "$REMOTE_URL" ]]; then
    # Validate that the URL starts with https://
    if [[ "$REMOTE_URL" != https://* ]]; then
        err "URL must start with https:// (e.g. https://github.com/user/repo.git)"
        exit 1
    fi

    # If the URL doesn't already contain a token, offer to add one
    if [[ "$REMOTE_URL" != *"@github.com"* && "$REMOTE_URL" == https://github.com/* ]]; then
        ask "Personal Access Token (leave empty for no auth):"
        read -r GIT_TOKEN
        if [[ -n "$GIT_TOKEN" ]]; then
            REMOTE_URL="${REMOTE_URL/https:\/\/github.com/https://x-access-token:${GIT_TOKEN}@github.com}"
            ok "Token embedded in remote URL."
        fi
    fi

    if [[ -n "$CURRENT_REMOTE" ]]; then
        git -C "$REPO_DIR" remote set-url origin "$REMOTE_URL"
        ok "Updated remote 'origin'."
    else
        git -C "$REPO_DIR" remote add origin "$REMOTE_URL"
        ok "Added remote 'origin'."
    fi
    sed_inplace "s|^GIT_REMOTE=.*|GIT_REMOTE=\"origin\"|" config.sh
    ok "Set GIT_REMOTE=origin in config.sh"

    # Initial push to sync repo/ with remote
    if git -C "$REPO_DIR" push -u origin main --force --quiet 2>/dev/null; then
        ok "Push to remote completed."
    else
        info "Could not push to remote. You may need to push manually."
    fi
else
    info "No remote configured. You can add one later in config.sh."
fi

# ── Cron job ──────────────────────────────────────────────────
CRON_CMD="${CRON_MINUTE:-30} ${CRON_HOUR:-9} * * * /usr/bin/env bash ${SCRIPT_DIR}/autocommit.sh # autocommit-pro"

# Remove any existing autocommit-pro entry, then add the new one
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
FILTERED_CRON=$(echo "$EXISTING_CRON" | grep -v '# autocommit-pro' || true)

if [[ -z "$FILTERED_CRON" ]]; then
    echo "$CRON_CMD" | crontab -
else
    printf '%s\n%s\n' "$FILTERED_CRON" "$CRON_CMD" | crontab -
fi
ok "Cron job installed: ${CRON_CMD}"

# ── Done ──────────────────────────────────────────────────────
echo ""
echo "=== Installation complete! ==="
echo ""
info "Run './install.sh' again to reconfigure any setting."
info "Run 'bash autocommit.sh' to test manually."
info "Run 'crontab -l' to verify the cron job."
echo ""
if [[ "$(uname -s)" == "Darwin" ]]; then
    info "macOS note: cron needs Full Disk Access."
    info "Go to System Settings > Privacy & Security > Full Disk Access"
    info "and add /usr/sbin/cron (use Cmd+Shift+G to navigate)."
    echo ""
fi
