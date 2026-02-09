#!/usr/bin/env bash
# autocommit-pro — Uninstaller
# Removes the cron job. Does NOT delete files or the repo.

set -euo pipefail

echo ""
echo "=== autocommit-pro — Uninstaller ==="
echo ""

# ── Read and filter crontab ───────────────────────────────────
EXISTING_CRON=$(crontab -l 2>/dev/null || true)

if ! echo "$EXISTING_CRON" | grep -q '# autocommit-pro'; then
    echo "  [INFO]  No autocommit-pro cron job found. Nothing to remove."
    exit 0
fi

FILTERED_CRON=$(echo "$EXISTING_CRON" | grep -v '# autocommit-pro' || true)

# Remove blank lines only
FILTERED_CRON=$(echo "$FILTERED_CRON" | sed '/^$/d' || true)

if [[ -z "$FILTERED_CRON" ]]; then
    crontab -r 2>/dev/null || true
    echo "  [OK]    Cron job removed (crontab is now empty)."
else
    echo "$FILTERED_CRON" | crontab -
    echo "  [OK]    autocommit-pro cron job removed."
fi

echo ""
echo "  [INFO]  Files and repository were NOT deleted."
echo "  [INFO]  To fully remove, delete the project directory manually."
echo ""
