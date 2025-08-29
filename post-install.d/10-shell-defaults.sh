#!/usr/bin/env bash
set -Eeuo pipefail
# Make zsh default if present
if command -v zsh >/dev/null 2>&1 && [[ "$SHELL" != "$(command -v zsh)" ]]; then
    chsh -s "$(command -v zsh)"
fi
