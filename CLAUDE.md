# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

autocommit-pro is a bash-only tool that automates GitHub contribution graph commits via cron. No external dependencies beyond bash 3.2+, git, and cron. Must work on both macOS and Linux.

## Architecture

Four scripts form the entire system:

- **`autocommit.sh`** — Main script executed by cron. Loads `config.sh`, evaluates a frequency gate (`should_run_today`), generates N random commits by appending to `repo/contributions.log`, and optionally pushes to a remote.
- **`install.sh`** — Interactive installer. Copies `config.sh.example` → `config.sh`, creates `repo/` as a separate git repo for contributions, configures remote with optional token auth, does initial force push, and sets up cron with `# autocommit-pro` marker.
- **`uninstall.sh`** — Removes cron entries matching `# autocommit-pro`. Does not delete files.
- **`config.sh.example`** — Template sourced as bash. Users copy to `config.sh` (gitignored).

**Key architectural decision:** `repo/` is a separate git repository from autocommit-pro itself. This allows the user to `git pull` tool updates without mixing history with contribution commits. `repo/` is gitignored. The install.sh ensures `repo/` branch is named `main` via `git branch -M main`.

**Token auth:** install.sh accepts either a full URL with embedded token (`https://x-access-token:TOKEN@github.com/...`) or a plain `https://github.com/...` URL followed by a separate token prompt. URLs must start with `https://`.

## Key Commands

```bash
./install.sh           # Full setup (interactive, asks for remote URL)
./autocommit.sh        # Manual test run
./uninstall.sh         # Remove cron job only
crontab -l             # Verify cron is installed
git pull               # Update tool without affecting repo/
```

## Cross-Platform Considerations

- **`sed -i`** differs: macOS requires `sed -i ''`, Linux uses `sed -i`. Use `uname -s` detection (see `sed_inplace` in `install.sh`).
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
