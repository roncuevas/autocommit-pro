#!/usr/bin/env bash
# Runs fast unit coverage followed by isolated Git integration scenarios.

set -euo pipefail
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$TEST_DIR/unit.sh"
bash "$TEST_DIR/integration.sh"
