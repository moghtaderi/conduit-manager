#!/bin/bash
#
# Build script for Conduit Manager
# Concatenates source modules into the final conduit.sh
#
# Usage: ./build.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
OUTPUT="$SCRIPT_DIR/conduit.sh"
BACKUP="$SCRIPT_DIR/conduit.sh.bak"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}Building conduit.sh from source modules...${NC}"

# Backup existing file
if [ -f "$OUTPUT" ]; then
    cp "$OUTPUT" "$BACKUP"
    echo -e "  ${YELLOW}Backed up existing conduit.sh${NC}"
fi

# Start with empty output
> "$OUTPUT"

# Function to append a source file
append() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: Source file not found: $file${NC}"
        exit 1
    fi
    cat "$file" >> "$OUTPUT"
}

echo "  Assembling installer section..."

#═══════════════════════════════════════════════════════════════════════
# Build order - Installer section
#═══════════════════════════════════════════════════════════════════════

append "$SRC_DIR/installer/00-header.sh"
append "$SRC_DIR/lib/colors.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/01-utils.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/02-detect-os.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/03-dependencies.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/04-settings.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/05-docker.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/06-backup-restore.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/07-verify.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/08-run.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/09-autostart.sh"

#═══════════════════════════════════════════════════════════════════════
# Build order - Management script heredoc wrapper start
#═══════════════════════════════════════════════════════════════════════

echo "" >> "$OUTPUT"
cat >> "$OUTPUT" << 'HEREDOC_WRAPPER_START'

#═══════════════════════════════════════════════════════════════════════
# Management Script
#═══════════════════════════════════════════════════════════════════════

create_management_script() {
    # Generate the management script.
    cat > "$INSTALL_DIR/conduit" << 'MANAGEMENT'
HEREDOC_WRAPPER_START

echo "  Assembling management script..."

#═══════════════════════════════════════════════════════════════════════
# Build order - Management script content
#═══════════════════════════════════════════════════════════════════════

append "$SRC_DIR/management/00-header.sh"
append "$SRC_DIR/management/01-docker-utils.sh"
append "$SRC_DIR/management/02-container-run.sh"
append "$SRC_DIR/management/03-headers.sh"
append "$SRC_DIR/management/04-node-identity.sh"
append "$SRC_DIR/management/05-dashboard.sh"
append "$SRC_DIR/management/06-container-stats.sh"
append "$SRC_DIR/management/07-live-stats.sh"
append "$SRC_DIR/management/08-format.sh"
append "$SRC_DIR/management/09-tracker.sh"
append "$SRC_DIR/management/10-advanced-stats.sh"
append "$SRC_DIR/management/11-peers.sh"
append "$SRC_DIR/management/12-status.sh"
append "$SRC_DIR/management/13-controls.sh"
append "$SRC_DIR/management/14-settings.sh"
append "$SRC_DIR/management/15-logs.sh"
append "$SRC_DIR/management/16-uninstall.sh"
append "$SRC_DIR/management/17-containers.sh"
append "$SRC_DIR/management/18-data-cap.sh"
append "$SRC_DIR/management/19-save-settings.sh"
append "$SRC_DIR/management/20-about.sh"
append "$SRC_DIR/management/21-settings-menu.sh"
append "$SRC_DIR/management/22-main-menu.sh"
append "$SRC_DIR/management/23-info-menu.sh"
append "$SRC_DIR/management/24-help.sh"
append "$SRC_DIR/management/25-health-check.sh"
append "$SRC_DIR/management/26-backup-restore.sh"
append "$SRC_DIR/management/27-update.sh"
append "$SRC_DIR/management/28-cli-dispatch.sh"

#═══════════════════════════════════════════════════════════════════════
# Build order - Heredoc wrapper end and post-install
#═══════════════════════════════════════════════════════════════════════

echo "  Assembling post-install section..."

append "$SRC_DIR/installer/10-management-close.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/11-summary.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/12-uninstall.sh"
echo "" >> "$OUTPUT"
append "$SRC_DIR/installer/13-main.sh"

# Make executable
chmod +x "$OUTPUT"

# Verify syntax
echo "  Verifying syntax..."
if bash -n "$OUTPUT" 2>&1; then
    echo -e "${GREEN}✓ Syntax valid${NC}"
else
    echo -e "${RED}✗ Syntax errors detected${NC}"
    # Restore backup
    if [ -f "$BACKUP" ]; then
        mv "$BACKUP" "$OUTPUT"
        echo -e "${YELLOW}Restored backup${NC}"
    fi
    exit 1
fi

# Show stats
lines=$(wc -l < "$OUTPUT")
size=$(du -h "$OUTPUT" | cut -f1)
echo -e "  Output: ${CYAN}$OUTPUT${NC}"
echo -e "  Lines:  ${CYAN}$lines${NC}"
echo -e "  Size:   ${CYAN}$size${NC}"

# Run tests if available
if [ -f "$SCRIPT_DIR/tests/test_conduit.sh" ]; then
    echo ""
    echo -e "${CYAN}Running tests...${NC}"
    if bash "$SCRIPT_DIR/tests/test_conduit.sh"; then
        echo ""
        echo -e "${GREEN}✓ All tests passed!${NC}"
    else
        echo ""
        echo -e "${RED}✗ Some tests failed${NC}"
        # Restore backup on test failure
        if [ -f "$BACKUP" ]; then
            mv "$BACKUP" "$OUTPUT"
            echo -e "${YELLOW}Restored backup due to test failure${NC}"
        fi
        exit 1
    fi
fi

# Cleanup backup on success
rm -f "$BACKUP"

echo ""
echo -e "${GREEN}Build complete!${NC}"
