# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

autocommit-pro is a Bash tool that automates GitHub contribution graph commits via cron. It supports Bash 3.2+, Git, cron, and standard Unix utilities on macOS and Linux.

## Architecture

The shell scripts and one shared helper form the system:

- **`autocommit.sh`** — Main script executed by cron. Loads and validates `config.sh`, takes an atomic per-destination lock, synchronizes before creating commits, and reports failed pushes without discarding local commits. `separate` appends to `repo/contributions.log`; `self` appends to `CHANGELOG.md` in the fork.
- **`common.sh`** — Shared defaults, validation, safe atomic config writing, and portable directory locking for Bash 3.2+.
- **`install.sh`** — Interactive installer. Validates before writing config, creates the separate destination without force-pushing, and updates cron only after setup succeeds.
- **`entrypoint.sh`** — Docker setup. Persists `separate` in `/app/repo` and clones `self` into the `/data` volume.
- **`uninstall.sh`** — Removes cron entries matching `# autocommit-pro`. Does not delete files.
- **`config.sh.example`** — Template sourced as bash. Users copy to `config.sh` (gitignored); `common.sh` validates it at install and runtime.

**Key architectural decision:** `DESTINATION_MODE=separate` uses the independent, gitignored `repo/`; `self` writes only to `CHANGELOG.md` in the fork checkout and uses a selected branch separate from `main` (default `autocommit-pro`). Both destinations refuse dirty worktrees and never force-push. Docker destinations live in persistent volumes.

**Git auth:** `GIT_AUTH_METHOD=gh` uses `gh auth login` and the official `gh auth setup-git` credential helper for HTTPS GitHub remotes; Docker requires `GH_TOKEN` or `GITHUB_TOKEN`. `token` retains URL-token or existing Git credential behavior. Never log raw Git stderr from credentialed remotes.

## Key Commands

```bash
./install.sh           # Full setup (interactive, asks for remote URL)
./autocommit.sh        # Manual test run
./uninstall.sh         # Remove cron job only
crontab -l             # Verify cron is installed
git pull               # Update tool without affecting repo/
```

## Cross-Platform Considerations

- Config writing uses a temporary file and atomic rename; use `printf %q` for shell-safe serialized values.
- **`autocommit.sh` exports PATH** with `/usr/local/bin:/opt/homebrew/bin` so git is found when running from cron on macOS.
- Shebangs use `#!/usr/bin/env bash`. Only bash 3.2+ features (macOS default).
- Scripts are committed with executable permissions (`100755`). Do not add `chmod +x` in install.sh — it causes unstaged changes that block `git pull`.

## Conventions

- Commit messages follow **Conventional Commits** format (e.g., `docs:`, `feat:`, `fix:`).
- **Never** add `Co-Authored-By` or any co-author trailer to commits.
- Prefer small, atomic commits — one logical change per commit.
- All scripts use `set -euo pipefail`.
- Cron entries are tagged with `# autocommit-pro` for reliable add/remove.
- `config.sh` is gitignored; `config.sh.example` is tracked.
- `repo/` is gitignored; it has its own `.git` independent from the tool repo.
- `bash tests/run.sh` exercises local bare remotes, installer validation, retry behavior, and Docker bootstrap using command stubs.
- The installer prompts for `GIT_BRANCH`; self mode must not target `main` or `master`. Docker accepts the same setting via environment.
