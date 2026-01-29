#!/bin/bash
#
# Extract modules from conduit.sh into separate source files
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$SCRIPT_DIR/conduit.sh"
OUT="$SCRIPT_DIR/src"

mkdir -p "$OUT/installer" "$OUT/management" "$OUT/lib"

# Helper to extract line range
extract() {
    local start=$1
    local end=$2
    local outfile=$3
    sed -n "${start},${end}p" "$SRC" > "$outfile"
    echo "  Created: $outfile (lines $start-$end)"
}

echo "Extracting modules from conduit.sh..."

#═══════════════════════════════════════════════════════════════════════
# Installer Section (lines 1-835)
#═══════════════════════════════════════════════════════════════════════

# Header and config (1-40)
extract 1 40 "$OUT/installer/00-header.sh"

# Colors (41-50)
extract 41 50 "$OUT/lib/colors.sh"

# Utils - print_header, logging, check_root (52-87)
extract 52 87 "$OUT/installer/01-utils.sh"

# OS Detection (89-157)
extract 89 157 "$OUT/installer/02-detect-os.sh"

# Package installation and dependencies (159-295)
extract 159 295 "$OUT/installer/03-dependencies.sh"

# RAM/CPU detection and settings prompt (296-488)
extract 296 488 "$OUT/installer/04-settings.sh"

# Docker installation (489-548)
extract 489 548 "$OUT/installer/05-docker.sh"

# Backup restore during install (549-627)
extract 549 627 "$OUT/installer/06-backup-restore.sh"

# Image verification (629-653)
extract 629 653 "$OUT/installer/07-verify.sh"

# Run container (654-711)
extract 654 711 "$OUT/installer/08-run.sh"

# Save settings and autostart (712-835)
extract 712 835 "$OUT/installer/09-autostart.sh"

#═══════════════════════════════════════════════════════════════════════
# Management Script Heredoc (lines 839-4214)
#═══════════════════════════════════════════════════════════════════════

# Management header (839-871)
extract 839 871 "$OUT/management/00-header.sh"

# Docker check and container helpers (872-961)
extract 872 961 "$OUT/management/01-docker-utils.sh"

# Container run and verify (962-1004)
extract 962 1004 "$OUT/management/02-container-run.sh"

# Print headers (1005-1050)
extract 1005 1050 "$OUT/management/03-headers.sh"

# Node identity and QR (1051-1146)
extract 1051 1146 "$OUT/management/04-node-identity.sh"

# Dashboard (1147-1289)
extract 1147 1289 "$OUT/management/05-dashboard.sh"

# Container stats (1290-1388)
extract 1290 1388 "$OUT/management/06-container-stats.sh"

# Live stats (1389-1451)
extract 1389 1451 "$OUT/management/07-live-stats.sh"

# Format bytes (1452-1476)
extract 1452 1476 "$OUT/management/08-format.sh"

# Tracker service (1477-1795)
extract 1477 1795 "$OUT/management/09-tracker.sh"

# Advanced stats (1796-2035)
extract 1796 2035 "$OUT/management/10-advanced-stats.sh"

# Peers view (2036-2253)
extract 2036 2253 "$OUT/management/11-peers.sh"

# Status display (2254-2503)
extract 2254 2503 "$OUT/management/12-status.sh"

# Start/stop/restart (2504-2634)
extract 2504 2634 "$OUT/management/13-controls.sh"

# Change settings (2635-2773)
extract 2635 2773 "$OUT/management/14-settings.sh"

# Logs display (2774-2805)
extract 2774 2805 "$OUT/management/15-logs.sh"

# Uninstall (2806-2925)
extract 2806 2925 "$OUT/management/16-uninstall.sh"

# Container management (2926-3182)
extract 2926 3182 "$OUT/management/17-containers.sh"

# Data cap (3183-3328)
extract 3183 3328 "$OUT/management/18-data-cap.sh"

# Save settings (3329-3349)
extract 3329 3349 "$OUT/management/19-save-settings.sh"

# About (3350-3385)
extract 3350 3385 "$OUT/management/20-about.sh"

# Settings menu (3386-3495)
extract 3386 3495 "$OUT/management/21-settings-menu.sh"

# Main menu (3496-3611)
extract 3496 3611 "$OUT/management/22-main-menu.sh"

# Info menu (3612-3788)
extract 3612 3788 "$OUT/management/23-info-menu.sh"

# Help and version (3789-3824)
extract 3789 3824 "$OUT/management/24-help.sh"

# Health check (3825-3974)
extract 3825 3974 "$OUT/management/25-health-check.sh"

# Backup/restore (3975-4143)
extract 3975 4143 "$OUT/management/26-backup-restore.sh"

# Update (4144-4193)
extract 4144 4193 "$OUT/management/27-update.sh"

# CLI dispatch (4195-4214)
extract 4195 4214 "$OUT/management/28-cli-dispatch.sh"

#═══════════════════════════════════════════════════════════════════════
# Post-heredoc section (lines 4217-4492)
#═══════════════════════════════════════════════════════════════════════

# Heredoc closing and management script creation (4217-4226)
extract 4217 4226 "$OUT/installer/10-management-close.sh"

# Summary (4228-4271)
extract 4228 4271 "$OUT/installer/11-summary.sh"

# Uninstall from installer (4273-4345)
extract 4273 4345 "$OUT/installer/12-uninstall.sh"

# Main entry point (4347-4492)
extract 4347 4492 "$OUT/installer/13-main.sh"

echo ""
echo "Extraction complete!"
echo "Total modules: $(find "$OUT" -name "*.sh" | wc -l | tr -d ' ')"
