save_settings_install() {
    mkdir -p "$INSTALL_DIR"
    cat > "$INSTALL_DIR/settings.conf" << EOF
MAX_CLIENTS=$MAX_CLIENTS
BANDWIDTH=$BANDWIDTH
CONTAINER_COUNT=${CONTAINER_COUNT:-1}
DATA_CAP_GB=0
DATA_CAP_IFACE=
DATA_CAP_BASELINE_RX=0
DATA_CAP_BASELINE_TX=0
DATA_CAP_PRIOR_USAGE=0
EOF

    chmod 600 "$INSTALL_DIR/settings.conf" 2>/dev/null || true

    if [ ! -f "$INSTALL_DIR/settings.conf" ]; then
        log_error "Failed to save settings. Check disk space and permissions."
        return 1
    fi

    log_success "Settings saved"
}

setup_autostart() {
    log_info "Setting up auto-start on boot..."
    
    if [ "$HAS_SYSTEMD" = "true" ]; then
        cat > /etc/systemd/system/conduit.service << EOF
[Unit]
Description=Psiphon Conduit Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/conduit start
ExecStop=/usr/local/bin/conduit stop

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload 2>/dev/null || true
        systemctl enable conduit.service 2>/dev/null || true
        systemctl start conduit.service 2>/dev/null || true
        log_success "Systemd service created, enabled, and started"
        
    elif command -v rc-update &>/dev/null; then
        # OpenRC (Alpine, Gentoo, etc.)
        cat > /etc/init.d/conduit << 'EOF'
#!/sbin/openrc-run

name="conduit"
description="Psiphon Conduit Service"
depend() {
    need docker
    after network
}
start() {
    ebegin "Starting Conduit"
    /usr/local/bin/conduit start
    eend $?
}
stop() {
    ebegin "Stopping Conduit"
    /usr/local/bin/conduit stop
    eend $?
}
EOF
        chmod +x /etc/init.d/conduit
        rc-update add conduit default 2>/dev/null || true
        log_success "OpenRC service created and enabled"
        
    elif [ -d /etc/init.d ]; then
        # SysVinit fallback
        cat > /etc/init.d/conduit << 'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          conduit
# Required-Start:    $docker
# Required-Stop:     $docker
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Psiphon Conduit Service
### END INIT INFO

case "$1" in
    start)
        /usr/local/bin/conduit start
        ;;
    stop)
        /usr/local/bin/conduit stop
        ;;
    restart)
        /usr/local/bin/conduit restart
        ;;
    status)
        docker ps | grep -q conduit && echo "Running" || echo "Stopped"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF
        chmod +x /etc/init.d/conduit
        if command -v update-rc.d &>/dev/null; then
            update-rc.d conduit defaults 2>/dev/null || true
        elif command -v chkconfig &>/dev/null; then
            chkconfig conduit on 2>/dev/null || true
        fi
        log_success "SysVinit service created and enabled"
        
    else
        log_warn "Could not set up auto-start. Docker's restart policy will handle restarts."
        log_info "Container is set to restart unless-stopped, which works on reboot if Docker starts."
    fi
}

#═══════════════════════════════════════════════════════════════════════
# Management Script
#═══════════════════════════════════════════════════════════════════════

