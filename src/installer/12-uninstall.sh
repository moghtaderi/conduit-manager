#═══════════════════════════════════════════════════════════════════════
# Uninstall Function
#═══════════════════════════════════════════════════════════════════════

uninstall() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo "║                    ⚠️  UNINSTALL CONDUIT                          "
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "This will completely remove:"
    echo "  • Conduit Docker container"
    echo "  • Conduit Docker image"
    echo "  • Conduit data volume (all stored data)"
    echo "  • Auto-start service (systemd/OpenRC/SysVinit)"
    echo "  • Configuration files"
    echo "  • Management CLI"
    echo ""
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    echo ""
    read -p "Are you sure you want to uninstall? (type 'yes' to confirm): " confirm < /dev/tty || true
    
    if [ "$confirm" != "yes" ]; then
        echo "Uninstall cancelled."
        exit 0
    fi
    
    echo ""
    log_info "Stopping Conduit container(s)..."
    for i in 1 2 3 4 5; do
        local cname="conduit"
        local vname="conduit-data"
        [ "$i" -gt 1 ] && cname="conduit-${i}" && vname="conduit-data-${i}"
        docker stop "$cname" 2>/dev/null || true
        docker rm -f "$cname" 2>/dev/null || true
        docker volume rm "$vname" 2>/dev/null || true
    done

    log_info "Removing Conduit Docker image..."
    docker rmi "$CONDUIT_IMAGE" 2>/dev/null || true
    
    log_info "Removing auto-start service..."
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
    
    log_info "Removing configuration files..."
    [ -n "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"
    rm -f /usr/local/bin/conduit
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    ✅ UNINSTALL COMPLETE!                         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Conduit and all related components have been removed."
    echo ""
    echo "Note: Docker itself was NOT removed."
    echo ""
}

#═══════════════════════════════════════════════════════════════════════
# Main
#═══════════════════════════════════════════════════════════════════════
