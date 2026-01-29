save_settings() {
    cat > "$INSTALL_DIR/settings.conf" << EOF
MAX_CLIENTS=$MAX_CLIENTS
BANDWIDTH=$BANDWIDTH
CONTAINER_COUNT=$CONTAINER_COUNT
DATA_CAP_GB=$DATA_CAP_GB
DATA_CAP_IFACE=$DATA_CAP_IFACE
DATA_CAP_BASELINE_RX=$DATA_CAP_BASELINE_RX
DATA_CAP_BASELINE_TX=$DATA_CAP_BASELINE_TX
DATA_CAP_PRIOR_USAGE=${DATA_CAP_PRIOR_USAGE:-0}
EOF
    # Save per-container overrides
    for i in $(seq 1 5); do
        local mc_var="MAX_CLIENTS_${i}"
        local bw_var="BANDWIDTH_${i}"
        [ -n "${!mc_var}" ] && echo "${mc_var}=${!mc_var}" >> "$INSTALL_DIR/settings.conf"
        [ -n "${!bw_var}" ] && echo "${bw_var}=${!bw_var}" >> "$INSTALL_DIR/settings.conf"
    done
    chmod 600 "$INSTALL_DIR/settings.conf" 2>/dev/null || true
}

