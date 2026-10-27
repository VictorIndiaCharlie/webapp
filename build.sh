#!/usr/bin/env bash
set -euo pipefail
OUT="/tmp/anagram-app.tar.gz"
rm -f "$OUT"
tar \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  --exclude='.venv' \
  --exclude='terraform' \
  --exclude='.terraform' \
  --exclude='terraform.tfstate*' \
  -czf "$OUT" \
  -C "$(dirname "$0")" .
echo "✓ Built $OUT ($(du -h "$OUT" | cut -f1))"
