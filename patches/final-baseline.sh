#!/usr/bin/env bash
set -euo pipefail

echo "=== rollback bad overwrite commit ==="

git revert --no-commit 8ed3357

git status --short