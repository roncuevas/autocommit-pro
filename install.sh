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

if [[ ! -f config.sh ]]; then
    cp config.sh.example config.sh
    sed_inplace "s|^INSTALL_DIR=.*|INSTALL_DIR=\"${SCRIPT_DIR}\"|" config.sh
    ok "Created config.sh from template."
else
    info "config.sh already exists — skipping."
fi

# Source config for cron schedule values
source config.sh

# ── Git identity ─────────────────────────────────────────────
echo ""
info "GitHub requires commits to use an email linked to your account."
info "Find your email at: https://github.com/settings/emails"
echo ""

ask "Git user name (e.g. John Doe):"
read -r INPUT_GIT_NAME
if [[ -z "$INPUT_GIT_NAME" ]]; then
    err "Git user name is required for GitHub to recognize your contributions."
    exit 1
fi

ask "Git email (must match your GitHub account):"
read -r INPUT_GIT_EMAIL
if [[ -z "$INPUT_GIT_EMAIL" ]]; then
    err "Git email is required for GitHub to recognize your contributions."
    exit 1
fi

sed_inplace "s|^GIT_USER_NAME=.*|GIT_USER_NAME=\"${INPUT_GIT_NAME}\"|" config.sh
sed_inplace "s|^GIT_USER_EMAIL=.*|GIT_USER_EMAIL=\"${INPUT_GIT_EMAIL}\"|" config.sh
ok "Set git identity: ${INPUT_GIT_NAME} <${INPUT_GIT_EMAIL}>"

# ── Contribution repo (separate from autocommit-pro) ─────────
if [[ ! -d "$REPO_DIR/.git" ]]; then
    mkdir -p "$REPO_DIR"
    git init --quiet "$REPO_DIR"
    git -C "$REPO_DIR" config user.name "$INPUT_GIT_NAME"
    git -C "$REPO_DIR" config user.email "$INPUT_GIT_EMAIL"
    echo "# autocommit-pro — contribution log" > "$REPO_DIR/contributions.log"
    git -C "$REPO_DIR" add contributions.log
    git -C "$REPO_DIR" commit -m "init: autocommit-pro" --quiet
    git -C "$REPO_DIR" branch -M main
    ok "Created repo/ with clean git history (branch: main)."
else
    info "repo/ already initialized — skipping."
fi

# ── Remote setup (optional) ──────────────────────────────────
echo ""
ask "GitHub remote URL starting with https:// (leave empty to skip):"
read -r REMOTE_URL

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

    if git -C "$REPO_DIR" remote get-url origin &>/dev/null; then
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
        ok "Initial push to remote completed."
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
info "Edit config.sh to customize commit frequency, range, etc."
info "Run 'bash autocommit.sh' to test manually."
info "Run 'crontab -l' to verify the cron job."
echo ""
if [[ "$(uname -s)" == "Darwin" ]]; then
    info "macOS note: cron needs Full Disk Access."
    info "Go to System Settings > Privacy & Security > Full Disk Access"
    info "and add /usr/sbin/cron (use Cmd+Shift+G to navigate)."
    echo ""
fi
