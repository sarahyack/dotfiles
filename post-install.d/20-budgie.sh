#!/usr/bin/env bash
set -Eeuo pipefail
# Example Budgie/GSettings tweaks (uncomment & change as you like):
gsettings set org.gnome.desktop.interface gtk-theme 'Material' || true
gsettings set org.gnome.desktop.interface icon-theme 'Qogir-Dark' || true
gsettings set org.gnome.desktop.interface cursor-theme 'Qogir-Dark' || true
gsettings set org.gnome.desktop.interface clock-format '24h'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

