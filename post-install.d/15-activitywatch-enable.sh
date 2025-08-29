#!/usr/bin/env bash
set -Eeuo pipefail
if systemctl --user >/dev/null 2>&1; then
    loginctl enable-linger "$USER" || true
    for unit in activitywatch.service aw-qt.service aw-server.service \
            aw-watcher-window.service aw-watcher-afk.service; do
        if systemctl --user list-unit-files | grep -q "^$unit"; then
            systemctl --user enable --now "$unit" || true
        fi
    done
fi
