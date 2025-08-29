#!/usr/bin/env bash
set -Eeuo pipefail
if command -v npm >/dev/null 2>&1; then
    npm install -g google-font-installer || true
fi
