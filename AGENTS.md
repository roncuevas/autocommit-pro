# Repository agent instructions

## Project

`autocommit-pro` is a Bash 3.2+ tool for scheduled GitHub contribution commits on macOS and Linux. See `README.md` for setup and configuration details.

## Architecture

- `common.sh` owns shared defaults, validation, safe config serialization, structured logging, and the per-destination lock.
- `install.sh` validates all answers before changing config or cron. Cron is updated only after repository setup succeeds.
- `autocommit.sh` validates configuration and repository state, synchronizes before creating commits, and preserves local commits if a push fails.
- `entrypoint.sh` initializes the Docker destination, persistent runtime config, logs, and cron.
- `DESTINATION_MODE=separate` writes to the independent `repo/` checkout. `self` writes to `CHANGELOG.md` in the user's fork on a separately selected branch; its default is `autocommit-pro` and `main`/`master` are forbidden.

## Safety invariants

- Never force-push or discard local commits and worktree changes automatically.
- Refuse to run against a dirty destination worktree.
- Prepare the configured branch without overwriting local changes. In self mode, publish only the selected branch and keep `main` unchanged.
- Never include raw Git stderr or shell commands in logs when they could expose remote credentials. Keep failure messages actionable and redact secrets.
- Write runtime configuration through a temporary file and atomic rename; serialize shell values with `printf %q`.
- Keep Docker destinations and logs in persistent volumes.
- Preserve Bash 3.2 compatibility and avoid adding runtime dependencies without a concrete need.

## Verification

- Run `bash tests/run.sh` for unit tests and isolated integration scenarios. Tests must use temporary local Git repositories or command stubs, never a real GitHub remote.
- Run `bash -n` on changed shell scripts, `git diff --check`, and `docker compose config --quiet` for relevant changes.
- A Docker image build requires an available Docker daemon; report when that proof could not run.

## Change conventions

- Follow Conventional Commits and keep each commit focused on one coherent change.
- Do not add co-author trailers.
- Do not include local editor state or secrets in commits.
