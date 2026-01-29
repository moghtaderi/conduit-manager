get_default_iface() {
    local iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
    [ -z "$iface" ] && iface=$(ip route list default 2>/dev/null | awk '{print $5}')
    echo "${iface:-eth0}"
}

# Get current data usage since baseline (in bytes)
get_data_usage() {
    local iface="${DATA_CAP_IFACE:-$(get_default_iface)}"
    if [ ! -f "/sys/class/net/$iface/statistics/rx_bytes" ]; then
        echo "0 0"
        return
    fi
    local rx=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
    local tx=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
    local used_rx=$((rx - DATA_CAP_BASELINE_RX))
    local used_tx=$((tx - DATA_CAP_BASELINE_TX))
    # Handle counter reset (reboot) - re-baseline to current counters
    # Prior usage is preserved in DATA_CAP_PRIOR_USAGE via check_data_cap
    if [ "$used_rx" -lt 0 ] || [ "$used_tx" -lt 0 ]; then
        DATA_CAP_BASELINE_RX=$rx
        DATA_CAP_BASELINE_TX=$tx
        save_settings
        used_rx=0
        used_tx=0
    fi
    echo "$used_rx $used_tx"
}

# Check data cap and stop containers if exceeded
# Returns 1 if cap exceeded, 0 if OK or no cap set
DATA_CAP_EXCEEDED=false
_DATA_CAP_LAST_SAVED=0
check_data_cap() {
    [ "$DATA_CAP_GB" -eq 0 ] 2>/dev/null && return 0
    # Validate DATA_CAP_GB is numeric
    if ! [[ "$DATA_CAP_GB" =~ ^[0-9]+$ ]]; then
        return 0  # invalid cap value, treat as no cap
    fi
    local usage=$(get_data_usage)
    local used_rx=$(echo "$usage" | awk '{print $1}')
    local used_tx=$(echo "$usage" | awk '{print $2}')
    local session_used=$((used_rx + used_tx))
    local total_used=$((session_used + ${DATA_CAP_PRIOR_USAGE:-0}))
    # Periodically persist usage so it survives reboots (save every ~100MB change)
    local save_threshold=104857600
    local diff=$((total_used - _DATA_CAP_LAST_SAVED))
    [ "$diff" -lt 0 ] && diff=$((-diff))
    if [ "$diff" -ge "$save_threshold" ]; then
        DATA_CAP_PRIOR_USAGE=$total_used
        DATA_CAP_BASELINE_RX=$(cat /sys/class/net/${DATA_CAP_IFACE:-$(get_default_iface)}/statistics/rx_bytes 2>/dev/null || echo 0)
        DATA_CAP_BASELINE_TX=$(cat /sys/class/net/${DATA_CAP_IFACE:-$(get_default_iface)}/statistics/tx_bytes 2>/dev/null || echo 0)
        save_settings
        _DATA_CAP_LAST_SAVED=$total_used
    fi
    local cap_bytes=$(awk -v gb="$DATA_CAP_GB" 'BEGIN{printf "%.0f", gb * 1073741824}')
    if [ "$total_used" -ge "$cap_bytes" ] 2>/dev/null; then
        # Only stop containers once when cap is first exceeded
        if [ "$DATA_CAP_EXCEEDED" = false ]; then
            DATA_CAP_EXCEEDED=true
            DATA_CAP_PRIOR_USAGE=$total_used
            DATA_CAP_BASELINE_RX=$(cat /sys/class/net/${DATA_CAP_IFACE:-$(get_default_iface)}/statistics/rx_bytes 2>/dev/null || echo 0)
            DATA_CAP_BASELINE_TX=$(cat /sys/class/net/${DATA_CAP_IFACE:-$(get_default_iface)}/statistics/tx_bytes 2>/dev/null || echo 0)
            save_settings
            _DATA_CAP_LAST_SAVED=$total_used
            for i in $(seq 1 $CONTAINER_COUNT); do
                local name=$(get_container_name $i)
                docker stop "$name" 2>/dev/null || true
            done
        fi
        return 1  # cap exceeded
    else
        DATA_CAP_EXCEEDED=false
    fi
    return 0
}

# Format bytes to GB with 2 decimal places
format_gb() {
    awk -v b="$1" 'BEGIN{printf "%.2f", b / 1073741824}'
}

set_data_cap() {
    local iface=$(get_default_iface)
    echo ""
    echo -e "${CYAN}═══ DATA USAGE CAP ═══${NC}"
    if [ "$DATA_CAP_GB" -gt 0 ] 2>/dev/null; then
        local usage=$(get_data_usage)
        local used_rx=$(echo "$usage" | awk '{print $1}')
        local used_tx=$(echo "$usage" | awk '{print $2}')
        local total_used=$((used_rx + used_tx))
        echo -e "  Current cap:   ${GREEN}${DATA_CAP_GB} GB${NC}"
        echo -e "  Used:          $(format_gb $total_used) GB"
        echo -e "  Interface:     ${DATA_CAP_IFACE:-$iface}"
    else
        echo -e "  Current cap:   ${YELLOW}None${NC}"
        echo -e "  Interface:     $iface"
    fi
    echo ""
    echo "  Options:"
    echo "    1. Set new data cap"
    echo "    2. Reset usage counter"
    echo "    3. Remove cap"
    echo "    4. Back"
    echo ""
    read -p "  Choice: " cap_choice < /dev/tty || true

    case "$cap_choice" in
        1)
            read -p "  Enter cap in GB (e.g. 50): " new_cap < /dev/tty || true
            if [[ "$new_cap" =~ ^[0-9]+$ ]] && [ "$new_cap" -gt 0 ]; then
                DATA_CAP_GB=$new_cap
                DATA_CAP_IFACE=$iface
                DATA_CAP_PRIOR_USAGE=0
                # Snapshot current bytes as baseline
                DATA_CAP_BASELINE_RX=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
                DATA_CAP_BASELINE_TX=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
                save_settings
                echo -e "  ${GREEN}✓ Data cap set to ${new_cap} GB on ${iface}${NC}"
            else
                echo -e "  ${RED}Invalid value.${NC}"
            fi
            ;;
        2)
            DATA_CAP_PRIOR_USAGE=0
            DATA_CAP_BASELINE_RX=$(cat /sys/class/net/${DATA_CAP_IFACE:-$iface}/statistics/rx_bytes 2>/dev/null || echo 0)
            DATA_CAP_BASELINE_TX=$(cat /sys/class/net/${DATA_CAP_IFACE:-$iface}/statistics/tx_bytes 2>/dev/null || echo 0)
            save_settings
            echo -e "  ${GREEN}✓ Usage counter reset${NC}"
            ;;
        3)
            DATA_CAP_GB=0
            DATA_CAP_BASELINE_RX=0
            DATA_CAP_BASELINE_TX=0
            DATA_CAP_PRIOR_USAGE=0
            DATA_CAP_IFACE=""
            save_settings
            echo -e "  ${GREEN}✓ Data cap removed${NC}"
            ;;
        4|"")
            return
            ;;
    esac
}

# Save all settings to file
