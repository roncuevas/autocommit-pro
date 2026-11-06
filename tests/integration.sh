#!/usr/bin/env bash
# Focused integration coverage; uses only local Git repositories and command stubs.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/autocommit-pro-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
PASS=0

pass() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
expect_failure() {
    local label="$1"; shift
    if "$@" >"${TMP_ROOT}/failure.out" 2>&1; then
        cat "${TMP_ROOT}/failure.out" >&2
        echo "not ok - ${label}: command unexpectedly succeeded" >&2
        exit 1
    fi
    pass "$label"
}
init_bare() { git init --bare --quiet "$1"; }
write_config() {
    local branch=main
    [[ "$2" == self ]] && branch=autocommit-pro
    cat > "$1/config.sh" <<EOF
DESTINATION_MODE=$2
MIN_COMMITS=1
MAX_COMMITS=1
FREQUENCY=daily
WEEKLY_DAY=1
RANDOM_CHANCE=50
CRON_HOUR=9
CRON_MINUTE=30
GIT_USER_NAME='Autocommit Test'
GIT_USER_EMAIL='autocommit@example.invalid'
GIT_REMOTE=$3
GIT_BRANCH=$branch
GIT_AUTH_METHOD=token
EOF
}

source "$ROOT/common.sh"
DESTINATION_MODE=separate MIN_COMMITS=08 MAX_COMMITS=09 FREQUENCY=weekly WEEKLY_DAY=07 RANDOM_CHANCE=50 CRON_HOUR=08 CRON_MINUTE=09 GIT_USER_NAME=Tester GIT_USER_EMAIL=test@example.invalid GIT_REMOTE='' GIT_BRANCH=main
set_defaults
validate_config installer >/dev/null
[[ "$MIN_COMMITS" == 8 && "$MAX_COMMITS" == 9 && "$WEEKLY_DAY" == 7 && "$CRON_HOUR" == 8 && "$CRON_MINUTE" == 9 ]]
pass "validates and normalizes leading-zero numeric settings"

CONFIG_ROUNDTRIP="${TMP_ROOT}/config-roundtrip.sh"
printf '# Keep comments and private extension settings.\nCUSTOM_SETTING=preserved\nMIN_COMMITS=999\n' > "$CONFIG_ROUNDTRIP"
write_runtime_config "$CONFIG_ROUNDTRIP" "$CONFIG_ROUNDTRIP"
(source "$CONFIG_ROUNDTRIP"; [[ "$CUSTOM_SETTING" == preserved && "$MIN_COMMITS" == 8 ]])
pass "rewrites configuration atomically while preserving custom settings"

if (DESTINATION_MODE=self MIN_COMMITS=1 MAX_COMMITS=1 FREQUENCY=daily GIT_USER_NAME=Tester GIT_USER_EMAIL=test@example.invalid GIT_REMOTE='' GIT_BRANCH=autocommit-pro; set_defaults; validate_config runtime >/dev/null 2>&1); then
    echo "not ok - rejects self mode without a remote" >&2; exit 1
fi
pass "rejects self mode without a remote"

# Invalid interactive settings must not write config, create a destination, or touch cron.
INSTALL_FIXTURE="${TMP_ROOT}/installer"
mkdir -p "$INSTALL_FIXTURE" "${TMP_ROOT}/bin"
cp "$ROOT/install.sh" "$ROOT/common.sh" "$ROOT/config.sh.example" "$INSTALL_FIXTURE/"
cat > "${TMP_ROOT}/bin/crontab" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -l ]]; then exit 1; fi
cat >/dev/null
touch "${TMP_ROOT}/crontab-was-written"
EOF
chmod +x "${TMP_ROOT}/bin/crontab"
printf 'token\nTester\ntest@example.invalid\n5\n2\ndaily\nseparate\nmain\n9\n30\n' | TMP_ROOT="$TMP_ROOT" PATH="${TMP_ROOT}/bin:$PATH" bash "${INSTALL_FIXTURE}/install.sh" >"${TMP_ROOT}/installer.out" 2>&1 && { echo 'not ok - installer rejects invalid commit range' >&2; exit 1; }
[[ ! -e "${INSTALL_FIXTURE}/config.sh" && ! -e "${INSTALL_FIXTURE}/repo" && ! -e "${TMP_ROOT}/crontab-was-written" ]]
pass "rejects invalid installer input before filesystem and cron changes"

# Successful local installation uses a non-force initial push and writes a quoted config.
VALID_INSTALL="${TMP_ROOT}/valid-installer"
INSTALL_REMOTE="${TMP_ROOT}/installer.git"
mkdir -p "$VALID_INSTALL" "${TMP_ROOT}/installer-bin"
cp "$ROOT/install.sh" "$ROOT/common.sh" "$ROOT/config.sh.example" "$VALID_INSTALL/"
init_bare "$INSTALL_REMOTE"
REAL_GIT=$(command -v git)
cat > "${TMP_ROOT}/installer-bin/git" <<EOF
#!/usr/bin/env bash
args=("\$@")
for ((i=0; i<\${#args[@]}; i++)); do
    if [[ "\${args[i]}" == https://mock.invalid/installer.git ]]; then args[i]="$INSTALL_REMOTE"; fi
done
exec "$REAL_GIT" "\${args[@]}"
EOF
cat > "${TMP_ROOT}/installer-bin/crontab" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == -l ]]; then
    [[ -f "$TMP_ROOT/cron-state" ]] && cat "$TMP_ROOT/cron-state"
    exit 0
fi
cat > "$TMP_ROOT/cron-state"
EOF
cat > "${TMP_ROOT}/installer-bin/gh" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == api ]]; then touch "$TMP_ROOT/token-gh-api-called"; exit 1; fi
exit 1
EOF
chmod +x "${TMP_ROOT}/installer-bin/git" "${TMP_ROOT}/installer-bin/gh" "${TMP_ROOT}/installer-bin/crontab"
printf "token\nAarón 'Test'\ntest@example.invalid\n1\n1\ndaily\nseparate\nmain\n9\n30\nhttps://mock.invalid/installer.git\n" | PATH="${TMP_ROOT}/installer-bin:$PATH" /bin/bash "${VALID_INSTALL}/install.sh" >"${TMP_ROOT}/installer-success.out" 2>&1
source "${VALID_INSTALL}/config.sh"
[[ "$GIT_USER_NAME" == "Aarón 'Test'" && "$GIT_REMOTE" == origin && "$GIT_BRANCH" == main ]]
[[ -f "${TMP_ROOT}/cron-state" && "$(git --git-dir="$INSTALL_REMOTE" rev-list --count main)" == 1 ]]
grep -q '# autocommit-pro' "${TMP_ROOT}/cron-state"
[[ ! -e "${TMP_ROOT}/token-gh-api-called" ]]
pass "successful installer stores shell-safe identity, pushes, and installs cron"

# The local gh path completes browser login when needed and configures Git's helper.
GH_INSTALL="${TMP_ROOT}/gh-installer"
GH_REMOTE="${TMP_ROOT}/gh-installer.git"
mkdir -p "$GH_INSTALL" "${TMP_ROOT}/gh-installer-bin"
cp "$ROOT/install.sh" "$ROOT/common.sh" "$ROOT/config.sh.example" "$GH_INSTALL/"
init_bare "$GH_REMOTE"
cat > "${TMP_ROOT}/gh-installer-bin/git" <<EOF
#!/usr/bin/env bash
args=("\$@")
for ((i=0; i<\${#args[@]}; i++)); do
    if [[ "\${args[i]}" == https://github.com/test/gh-install.git ]]; then args[i]="$GH_REMOTE"; fi
done
exec "$REAL_GIT" "\${args[@]}"
EOF
cat > "${TMP_ROOT}/gh-installer-bin/gh" <<EOF
#!/usr/bin/env bash
case "\${1:-} \${2:-}" in
    'auth status') [[ -f "$TMP_ROOT/gh-login-complete" ]] ;;
    'auth login') touch "$TMP_ROOT/gh-login-complete" ;;
    'auth setup-git') echo "\$*" >> "$TMP_ROOT/gh-commands" ;;
    'api user') printf '%s\\n' 'GitHub Sample User' ;;
    'api user/emails')
        [[ ! -f "$TMP_ROOT/gh-no-email" ]] || exit 1
        printf '%s\\n' 'github-sample@example.invalid'
        ;;
    *) exit 2 ;;
esac
EOF
cp "${TMP_ROOT}/installer-bin/crontab" "${TMP_ROOT}/gh-installer-bin/crontab"
chmod +x "${TMP_ROOT}/gh-installer-bin/git" "${TMP_ROOT}/gh-installer-bin/gh" "${TMP_ROOT}/gh-installer-bin/crontab"
printf "gh\n\n\n\n\n\n\n\n\n\nhttps://github.com/test/gh-install.git\n" | PATH="${TMP_ROOT}/gh-installer-bin:$PATH" /bin/bash "${GH_INSTALL}/install.sh" >"${TMP_ROOT}/gh-installer.out" 2>&1
source "${GH_INSTALL}/config.sh"
[[ "$GIT_AUTH_METHOD" == gh && -f "${TMP_ROOT}/gh-login-complete" ]]
[[ "$GIT_USER_NAME" == 'GitHub Sample User' && "$GIT_USER_EMAIL" == 'github-sample@example.invalid' ]]
grep -q 'auth setup-git --force --hostname github.com' "${TMP_ROOT}/gh-commands"
[[ "$(git --git-dir="$GH_REMOTE" rev-list --count main)" == 1 ]]
pass "installer authenticates first and suggests the GitHub profile identity"

# Missing email access falls back to a manual value without requesting extra scopes.
touch "${TMP_ROOT}/gh-no-email"
git -C "${GH_INSTALL}/repo" remote set-url origin https://github.com/test/gh-install.git
awk '!/^GIT_USER_EMAIL=/' "${GH_INSTALL}/config.sh" > "${GH_INSTALL}/config.sh.tmp"
mv "${GH_INSTALL}/config.sh.tmp" "${GH_INSTALL}/config.sh"
printf "\n\nmanual@example.invalid\n\n\n\n\n\n\n\n\n" | PATH="${TMP_ROOT}/gh-installer-bin:$PATH" /bin/bash "${GH_INSTALL}/install.sh" >"${TMP_ROOT}/gh-installer-fallback.out" 2>&1
source "${GH_INSTALL}/config.sh"
[[ "$GIT_USER_NAME" == 'GitHub Sample User' && "$GIT_USER_EMAIL" == manual@example.invalid ]]
grep -q 'Could not retrieve the primary verified GitHub email' "${TMP_ROOT}/gh-installer-fallback.out"
pass "installer asks for email manually when gh cannot read it"

# Self installation creates/publishes the selected non-main branch and leaves main unchanged.
SELF_INSTALL="${TMP_ROOT}/self-installer"
SELF_INSTALL_REMOTE="${TMP_ROOT}/self-installer.git"
mkdir -p "$SELF_INSTALL"
init_bare "$SELF_INSTALL_REMOTE"
git init --quiet "$SELF_INSTALL"
git -C "$SELF_INSTALL" checkout -b main >/dev/null 2>&1
cp "$ROOT/install.sh" "$ROOT/common.sh" "$ROOT/config.sh.example" "$ROOT/.gitignore" "$SELF_INSTALL/"
git -C "$SELF_INSTALL" add .
git -C "$SELF_INSTALL" -c user.name=Tester -c user.email=test@example.invalid commit --quiet -m init
git -C "$SELF_INSTALL" remote add origin "$SELF_INSTALL_REMOTE"
git -C "$SELF_INSTALL" push -u origin main --quiet
SELF_MAIN_BEFORE=$(git --git-dir="$SELF_INSTALL_REMOTE" rev-parse main)
cp "${TMP_ROOT}/installer-bin/crontab" "${TMP_ROOT}/self-installer-crontab"
chmod +x "${TMP_ROOT}/self-installer-crontab"
mkdir -p "${TMP_ROOT}/self-installer-bin"
cp "${TMP_ROOT}/self-installer-crontab" "${TMP_ROOT}/self-installer-bin/crontab"
printf "token\nTester\ntest@example.invalid\n1\n1\ndaily\nself\nactivity-log\n9\n30\n" | PATH="${TMP_ROOT}/self-installer-bin:$PATH" bash "${SELF_INSTALL}/install.sh" >"${TMP_ROOT}/self-installer.out" 2>&1
source "${SELF_INSTALL}/config.sh"
[[ "$GIT_BRANCH" == activity-log && "$(git -C "$SELF_INSTALL" branch --show-current)" == activity-log ]]
[[ "$(git --git-dir="$SELF_INSTALL_REMOTE" rev-parse main)" == "$SELF_MAIN_BEFORE" ]]
[[ "$(git --git-dir="$SELF_INSTALL_REMOTE" rev-parse activity-log)" == "$SELF_MAIN_BEFORE" ]]
pass "self installer selects and publishes a separate branch without changing main"

# Build a self destination with a local bare fork.
SELF_REMOTE="${TMP_ROOT}/self.git"
SELF_APP="${TMP_ROOT}/self-app"
init_bare "$SELF_REMOTE"
git init --quiet "$SELF_APP"
git -C "$SELF_APP" checkout -b main >/dev/null 2>&1
cp "$ROOT/autocommit.sh" "$ROOT/common.sh" "$ROOT/.gitignore" "$SELF_APP/"
printf '# Changelog\n' > "${SELF_APP}/CHANGELOG.md"
printf 'project\n' > "${SELF_APP}/README.md"
write_config "$SELF_APP" self origin
git -C "$SELF_APP" add .
git -C "$SELF_APP" -c user.name=Tester -c user.email=test@example.invalid commit --quiet -m init
git -C "$SELF_APP" remote add origin "$SELF_REMOTE"
git -C "$SELF_APP" push origin main --quiet
git -C "$SELF_APP" branch autocommit-pro main
git -C "$SELF_APP" checkout autocommit-pro >/dev/null 2>&1
git -C "$SELF_APP" push -u origin autocommit-pro --quiet
MAIN_BEFORE=$(git --git-dir="$SELF_REMOTE" rev-parse main)

run_self() { bash "${SELF_APP}/autocommit.sh"; }
run_self
[[ "$(git --git-dir="$SELF_REMOTE" rev-list --count autocommit-pro)" == 2 ]]
[[ "$(git --git-dir="$SELF_REMOTE" rev-parse main)" == "$MAIN_BEFORE" ]]
grep -q 'autocommit #1/1' "${SELF_APP}/CHANGELOG.md"
pass "self mode commits the changelog and pushes it to the fork"

# Dirty worktrees are rejected without creating a commit.
printf 'local edit\n' >> "${SELF_APP}/README.md"
BEFORE=$(git -C "$SELF_APP" rev-parse HEAD)
expect_failure "self mode rejects dirty worktrees" run_self
[[ "$(git -C "$SELF_APP" rev-parse HEAD)" == "$BEFORE" ]]
git -C "$SELF_APP" checkout -- README.md

# A failed remote update creates no commit and leaves the local branch untouched.
git -C "$SELF_APP" remote set-url origin "${TMP_ROOT}/missing.git"
BEFORE=$(git -C "$SELF_APP" rev-parse HEAD)
expect_failure "sync failure stops before creating commits" run_self
[[ "$(git -C "$SELF_APP" rev-parse HEAD)" == "$BEFORE" ]]
git -C "$SELF_APP" remote set-url origin "$SELF_REMOTE"

# A rejected push preserves the new local commit; the next run pushes it.
mkdir -p "${SELF_REMOTE}/hooks"
cat > "${SELF_REMOTE}/hooks/pre-receive" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "${SELF_REMOTE}/hooks/pre-receive"
BEFORE=$(git -C "$SELF_APP" rev-parse HEAD)
expect_failure "push failure is visible and returns nonzero" run_self
[[ "$(git -C "$SELF_APP" rev-parse HEAD)" != "$BEFORE" ]]
grep -q '\[ERROR\].*Push failed' "${SELF_APP}/autocommit.log"
rm "${SELF_REMOTE}/hooks/pre-receive"
run_self
[[ "$(git --git-dir="$SELF_REMOTE" rev-parse autocommit-pro)" == "$(git -C "$SELF_APP" rev-parse HEAD)" ]]
[[ "$(git --git-dir="$SELF_REMOTE" rev-parse main)" == "$MAIN_BEFORE" ]]
pass "push failure retains commits and a later run publishes them"

# A second invocation cannot overlap a push already in progress.
CONCURRENCY_MARKER="${TMP_ROOT}/push-started"
cat > "${SELF_REMOTE}/hooks/pre-receive" <<EOF
#!/bin/sh
touch "$CONCURRENCY_MARKER"
sleep 2
exit 1
EOF
chmod +x "${SELF_REMOTE}/hooks/pre-receive"
run_self >"${TMP_ROOT}/concurrent-first.out" 2>&1 &
FIRST_PID=$!
ATTEMPTS=0
while [[ ! -f "$CONCURRENCY_MARKER" && "$ATTEMPTS" -lt 8 ]]; do sleep 1; ATTEMPTS=$((ATTEMPTS + 1)); done
[[ -f "$CONCURRENCY_MARKER" ]] || { echo 'not ok - first run did not reach the push hook' >&2; exit 1; }
expect_failure "overlapping invocation is rejected by the lock" run_self
if wait "$FIRST_PID"; then echo 'not ok - simulated push rejection unexpectedly succeeded' >&2; exit 1; fi
rm "${SELF_REMOTE}/hooks/pre-receive"
run_self
pass "lock is released after a failed run"

# The separate destination uses the same sync/commit/push failure contract.
SEPARATE_REMOTE="${TMP_ROOT}/separate.git"
init_bare "$SEPARATE_REMOTE"
mkdir -p "${SELF_APP}/repo"
git init --quiet "${SELF_APP}/repo"
git -C "${SELF_APP}/repo" checkout -b main >/dev/null 2>&1
printf '# contributions\n' > "${SELF_APP}/repo/contributions.log"
git -C "${SELF_APP}/repo" add contributions.log
git -C "${SELF_APP}/repo" -c user.name=Tester -c user.email=test@example.invalid commit --quiet -m init
git -C "${SELF_APP}/repo" remote add origin "$SEPARATE_REMOTE"
git -C "${SELF_APP}/repo" push -u origin main --quiet
write_config "$SELF_APP" separate origin
bash "${SELF_APP}/autocommit.sh"
[[ "$(git --git-dir="$SEPARATE_REMOTE" rev-list --count main)" == 2 ]]
grep -q 'autocommit #1/1' "${SELF_APP}/repo/contributions.log"
pass "separate mode commits and pushes contributions.log"

DOCKER_SEPARATE_REMOTE="${TMP_ROOT}/docker-separate.git"
init_bare "$DOCKER_SEPARATE_REMOTE"

# Installer/entrypoint clone uses a persistent volume and does not need Docker daemon.
DOCKER_IMAGE="${TMP_ROOT}/image"
DOCKER_DATA="${TMP_ROOT}/data"
mkdir -p "$DOCKER_IMAGE" "${TMP_ROOT}/docker-bin" "$DOCKER_DATA"
cp "$ROOT/entrypoint.sh" "$ROOT/common.sh" "$DOCKER_IMAGE/"
REAL_GIT=$(command -v git)
cat > "${TMP_ROOT}/docker-bin/git" <<EOF
#!/usr/bin/env bash
args=("\$@")
for ((i=0; i<\${#args[@]}; i++)); do
    if [[ "\${args[i]}" == https://github.com/test/fork.git ]]; then args[i]="$SELF_REMOTE"; fi
    if [[ "\${args[i]}" == https://mock.invalid/separate.git ]]; then args[i]="$DOCKER_SEPARATE_REMOTE"; fi
done
exec "$REAL_GIT" "\${args[@]}"
EOF
cat > "${TMP_ROOT}/docker-bin/crontab" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
EOF
cat > "${TMP_ROOT}/docker-bin/crond" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${TMP_ROOT}/docker-bin/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
    'auth status '*) exit 0 ;;
    'auth setup-git '*) echo "\$*" >> "$TMP_ROOT/docker-gh-commands" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "${TMP_ROOT}/docker-bin/git" "${TMP_ROOT}/docker-bin/gh" "${TMP_ROOT}/docker-bin/crontab" "${TMP_ROOT}/docker-bin/crond"
NO_TOKEN_DATA="${TMP_ROOT}/no-token-data"
expect_failure "Docker gh mode requires a noninteractive token" env DESTINATION_MODE=self GIT_AUTH_METHOD=gh REMOTE_URL=https://github.com/test/fork.git GIT_USER_NAME=Tester GIT_USER_EMAIL=test@example.invalid DATA_DIR="$NO_TOKEN_DATA" LOG_FILE="$TMP_ROOT/docker-no-token.log" PATH="${TMP_ROOT}/docker-bin:$PATH" bash "${DOCKER_IMAGE}/entrypoint.sh"
[[ ! -e "$NO_TOKEN_DATA" ]]
if ! DESTINATION_MODE=self GIT_AUTH_METHOD=gh REMOTE_URL=https://x-access-token:secret@github.com/test/fork.git GH_TOKEN=dummy GIT_USER_NAME=Tester GIT_USER_EMAIL=test@example.invalid DATA_DIR="$DOCKER_DATA" LOG_FILE="$TMP_ROOT/docker-self.log" PATH="${TMP_ROOT}/docker-bin:$PATH" bash "${DOCKER_IMAGE}/entrypoint.sh" >"${TMP_ROOT}/docker.out" 2>&1; then
    cat "${TMP_ROOT}/docker.out" >&2
    exit 1
fi
[[ -f "${DOCKER_DATA}/autocommit-pro/.git/config" && -f "${DOCKER_DATA}/autocommit-pro/config.sh" ]]
grep -q 'auth setup-git --force --hostname github.com' "${TMP_ROOT}/docker-gh-commands"
! grep -q 'secret' "${DOCKER_DATA}/autocommit-pro/.git/config"
grep -q '\[INFO\].*Cloned the fork' "$TMP_ROOT/docker-self.log"
pass "Docker uses GH_TOKEN through gh and strips credentials from the fork remote"

SEPARATE_IMAGE="${TMP_ROOT}/separate-image"
mkdir -p "$SEPARATE_IMAGE"
cp "$ROOT/entrypoint.sh" "$ROOT/common.sh" "$SEPARATE_IMAGE/"
if ! DESTINATION_MODE=separate REMOTE_URL=https://mock.invalid/separate.git GIT_USER_NAME=Tester GIT_USER_EMAIL=test@example.invalid LOG_FILE="$TMP_ROOT/docker-separate.log" PATH="${TMP_ROOT}/docker-bin:$PATH" bash "${SEPARATE_IMAGE}/entrypoint.sh" >"${TMP_ROOT}/docker-separate.out" 2>&1; then
    cat "${TMP_ROOT}/docker-separate.out" >&2
    exit 1
fi
[[ -d "${SEPARATE_IMAGE}/repo/.git" && "$(git --git-dir="$DOCKER_SEPARATE_REMOTE" rev-list --count main)" == 1 ]]
pass "Docker separate mode persists and initializes repo/ without force-push"

echo "1..${PASS}"
