#!/usr/bin/env bash
# autocommit-pro — Docker Entrypoint
# Generates config, initializes repo, installs cron, and runs crond.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/repo"

# ── Helpers ───────────────────────────────────────────────────
info() { echo "  [INFO]  $*"; }
ok()   { echo "  [OK]    $*"; }
err()  { echo "  [ERROR] $*" >&2; }

# ── Validate required variables ──────────────────────────────
if [[ -z "${REMOTE_URL:-}" ]]; then
    err "REMOTE_URL is required."
    err "Example: docker run -e REMOTE_URL='https://x-access-token:TOKEN@github.com/user/repo.git' ..."
    exit 1
fi

if [[ "$REMOTE_URL" != https://* ]]; then
    err "REMOTE_URL must start with https://"
    exit 1
fi

if [[ -z "${GIT_USER_NAME:-}" || -z "${GIT_USER_EMAIL:-}" ]]; then
    err "GIT_USER_NAME and GIT_USER_EMAIL are required."
    err "The email must match one linked to your GitHub account."
    err "Example: docker run -e GIT_USER_NAME='John Doe' -e GIT_USER_EMAIL='john@users.noreply.github.com' ..."
    exit 1
fi

echo ""
echo "=== autocommit-pro — Docker Setup ==="
echo ""

# ── Generate config.sh from environment variables ────────────
cat > "${SCRIPT_DIR}/config.sh" <<EOF
#!/usr/bin/env bash
MIN_COMMITS=${MIN_COMMITS:-1}
MAX_COMMITS=${MAX_COMMITS:-5}
FREQUENCY="${FREQUENCY:-daily}"
WEEKLY_DAY=${WEEKLY_DAY:-1}
RANDOM_CHANCE=${RANDOM_CHANCE:-50}
CRON_HOUR=${CRON_HOUR:-9}
CRON_MINUTE=${CRON_MINUTE:-30}
GIT_USER_NAME="${GIT_USER_NAME}"
GIT_USER_EMAIL="${GIT_USER_EMAIL}"
GIT_REMOTE="origin"
GIT_BRANCH="${GIT_BRANCH:-main}"
INSTALL_DIR="${SCRIPT_DIR}"
EOF
ok "Generated config.sh"

# ── Initialize repo/ ────────────────────────────────────────
if [[ ! -d "$REPO_DIR/.git" ]]; then
    mkdir -p "$REPO_DIR"
    git init --quiet "$REPO_DIR"
    echo "# autocommit-pro — contribution log" > "$REPO_DIR/contributions.log"
    git -C "$REPO_DIR" add contributions.log
    git -C "$REPO_DIR" commit -m "init: autocommit-pro" --quiet
    git -C "$REPO_DIR" branch -M main
    ok "Initialized repo/ (branch: main)."
fi

# ── Configure remote ────────────────────────────────────────
if git -C "$REPO_DIR" remote get-url origin &>/dev/null; then
    git -C "$REPO_DIR" remote set-url origin "$REMOTE_URL"
else
    git -C "$REPO_DIR" remote add origin "$REMOTE_URL"
fi
ok "Remote 'origin' configured."

# ── Initial push ────────────────────────────────────────────
GIT_BRANCH="${GIT_BRANCH:-main}"
if git -C "$REPO_DIR" push -u origin "$GIT_BRANCH" --force --quiet 2>/dev/null; then
    ok "Initial push to origin/${GIT_BRANCH} completed."
else
    info "Could not push to remote. Will retry on next cron run."
fi

# ── Install cron job ────────────────────────────────────────
CRON_MINUTE="${CRON_MINUTE:-30}"
CRON_HOUR="${CRON_HOUR:-9}"
CRON_CMD="${CRON_MINUTE} ${CRON_HOUR} * * * /usr/bin/env bash ${SCRIPT_DIR}/autocommit.sh # autocommit-pro"

echo "$CRON_CMD" | crontab -
ok "Cron job installed: ${CRON_CMD}"

# ── Summary ─────────────────────────────────────────────────
echo ""
echo "=== Setup complete! ==="
echo ""
info "Frequency: ${FREQUENCY:-daily}"
info "Commits per run: ${MIN_COMMITS:-1}–${MAX_COMMITS:-5}"
info "Timezone: ${TZ:-UTC}"
info "Starting crond in foreground..."
echo ""

# ── Run crond in foreground ─────────────────────────────────
exec crond -f -l 2
