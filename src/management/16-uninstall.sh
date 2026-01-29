uninstall_all() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                    ⚠️  UNINSTALL CONDUIT                          ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This will completely remove:"
    echo "  • All Conduit Docker containers (conduit, conduit-2..5)"
    echo "  • All Conduit data volumes"
    echo "  • Conduit Docker image"
    echo "  • Auto-start service (systemd/OpenRC/SysVinit)"
    echo "  • Background tracker service & stats data"
    echo "  • Configuration files & Management CLI"
    echo ""
    echo -e "${YELLOW}Docker engine will NOT be removed.${NC}"
    echo ""
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    echo ""
    read -p "Are you sure you want to uninstall? (type 'yes' to confirm): " confirm < /dev/tty || true

    if [ "$confirm" != "yes" ]; then
        echo "Uninstall cancelled."
        return 0
    fi

    # Check for backup keys
    local keep_backups=false
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo ""
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  📁 Backup keys found in: ${BACKUP_DIR}${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "You have backed up node identity keys. These allow you to restore"
        echo "your node identity if you reinstall Conduit later."
        echo ""
        while true; do
            read -p "Do you want to KEEP your backup keys? (y/n): " keep_confirm < /dev/tty || true
            if [[ "$keep_confirm" =~ ^[Yy]$ ]]; then
                keep_backups=true
                echo -e "${GREEN}✓ Backup keys will be preserved.${NC}"
                break
            elif [[ "$keep_confirm" =~ ^[Nn]$ ]]; then
                echo -e "${YELLOW}⚠ Backup keys will be deleted.${NC}"
                break
            else
                echo "Please enter y or n."
            fi
        done
        echo ""
    fi

    echo ""
    echo -e "${BLUE}[INFO]${NC} Stopping Conduit container(s)..."
    for i in $(seq 1 5); do
        local name=$(get_container_name $i)
        docker stop "$name" 2>/dev/null || true
        docker rm -f "$name" 2>/dev/null || true
    done

    echo -e "${BLUE}[INFO]${NC} Removing Conduit Docker image..."
    docker rmi "$CONDUIT_IMAGE" 2>/dev/null || true

    echo -e "${BLUE}[INFO]${NC} Removing Conduit data volume(s)..."
    for i in $(seq 1 5); do
        local vol=$(get_volume_name $i)
        docker volume rm "$vol" 2>/dev/null || true
    done

    echo -e "${BLUE}[INFO]${NC} Removing auto-start service..."
    # Tracker service
    systemctl stop conduit-tracker.service 2>/dev/null || true
    systemctl disable conduit-tracker.service 2>/dev/null || true
    rm -f /etc/systemd/system/conduit-tracker.service
    pkill -f "conduit-tracker.sh" 2>/dev/null || true
    # Systemd
    systemctl stop conduit.service 2>/dev/null || true
    systemctl disable conduit.service 2>/dev/null || true
    rm -f /etc/systemd/system/conduit.service
    systemctl daemon-reload 2>/dev/null || true
    # OpenRC / SysVinit
    rc-service conduit stop 2>/dev/null || true
    rc-update del conduit 2>/dev/null || true
    service conduit stop 2>/dev/null || true
    update-rc.d conduit remove 2>/dev/null || true
    chkconfig conduit off 2>/dev/null || true
    rm -f /etc/init.d/conduit

    echo -e "${BLUE}[INFO]${NC} Removing configuration files..."
    if [ "$keep_backups" = true ]; then
        # Keep backup directory, remove everything else in /opt/conduit
        echo -e "${BLUE}[INFO]${NC} Preserving backup keys in ${BACKUP_DIR}..."
        # Remove files in /opt/conduit but keep backups subdirectory
        rm -f /opt/conduit/config.env 2>/dev/null || true
        rm -f /opt/conduit/conduit 2>/dev/null || true
        rm -f /opt/conduit/conduit-tracker.sh 2>/dev/null || true
        rm -rf /opt/conduit/traffic_stats 2>/dev/null || true
        find /opt/conduit -maxdepth 1 -type f -delete 2>/dev/null || true
    else
        # Remove everything including backups
        rm -rf /opt/conduit
    fi
    rm -f /usr/local/bin/conduit

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    ✅ UNINSTALL COMPLETE!                         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Conduit and all related components have been removed."
    if [ "$keep_backups" = true ]; then
        echo ""
        echo -e "${CYAN}📁 Your backup keys are preserved in: ${BACKUP_DIR}${NC}"
        echo "   You can use these to restore your node identity after reinstalling."
    fi
    echo ""
    echo "Note: Docker engine was NOT removed."
    echo ""
}

