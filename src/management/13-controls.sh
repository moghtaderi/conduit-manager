start_conduit() {
    # Check data cap before starting
    if [ "$DATA_CAP_GB" -gt 0 ] 2>/dev/null; then
        local usage=$(get_data_usage)
        local used_rx=$(echo "$usage" | awk '{print $1}')
        local used_tx=$(echo "$usage" | awk '{print $2}')
        local total_used=$((used_rx + used_tx + ${DATA_CAP_PRIOR_USAGE:-0}))
        local cap_bytes=$(awk -v gb="$DATA_CAP_GB" 'BEGIN{printf "%.0f", gb * 1073741824}')
        if [ "$total_used" -ge "$cap_bytes" ] 2>/dev/null; then
            echo -e "${RED}⚠ Data cap exceeded ($(format_gb $total_used) / ${DATA_CAP_GB} GB). Containers will not start.${NC}"
            echo -e "${YELLOW}Reset or increase the data cap from the menu to start containers.${NC}"
            return 1
        fi
    fi

    echo "Starting Conduit ($CONTAINER_COUNT container(s))..."

    for i in $(seq 1 $CONTAINER_COUNT); do
        local name=$(get_container_name $i)
        local vol=$(get_volume_name $i)

        # Check if container exists (running or stopped)
        if docker ps -a 2>/dev/null | grep -q "[[:space:]]${name}$"; then
            if docker ps 2>/dev/null | grep -q "[[:space:]]${name}$"; then
                echo -e "${GREEN}✓ ${name} is already running${NC}"
                continue
            fi
            echo "Recreating ${name}..."
            docker rm "$name" 2>/dev/null || true
        fi

        docker volume create "$vol" 2>/dev/null || true
        fix_volume_permissions $i
        run_conduit_container $i

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ ${name} started${NC}"
        else
            echo -e "${RED}✗ Failed to start ${name}${NC}"
        fi
    done
    # Start background tracker
    setup_tracker_service 2>/dev/null || true
    return 0
}

stop_conduit() {
    echo "Stopping Conduit..."
    local stopped=0
    for i in $(seq 1 $CONTAINER_COUNT); do
        local name=$(get_container_name $i)
        if docker ps 2>/dev/null | grep -q "[[:space:]]${name}$"; then
            docker stop "$name" 2>/dev/null
            echo -e "${YELLOW}✓ ${name} stopped${NC}"
            stopped=$((stopped + 1))
        fi
    done
    # Also stop any extra containers beyond current count (from previous scaling)
    for i in $(seq $((CONTAINER_COUNT + 1)) 5); do
        local name=$(get_container_name $i)
        if docker ps -a 2>/dev/null | grep -q "[[:space:]]${name}$"; then
            docker stop "$name" 2>/dev/null || true
            docker rm "$name" 2>/dev/null || true
            echo -e "${YELLOW}✓ ${name} stopped and removed (extra)${NC}"
        fi
    done
    [ "$stopped" -eq 0 ] && echo -e "${YELLOW}No Conduit containers are running${NC}"
    # Stop background tracker
    stop_tracker_service 2>/dev/null || true
    return 0
}

restart_conduit() {
    # Check data cap before restarting
    if [ "$DATA_CAP_GB" -gt 0 ] 2>/dev/null; then
        local usage=$(get_data_usage)
        local used_rx=$(echo "$usage" | awk '{print $1}')
        local used_tx=$(echo "$usage" | awk '{print $2}')
        local total_used=$((used_rx + used_tx + ${DATA_CAP_PRIOR_USAGE:-0}))
        local cap_bytes=$(awk -v gb="$DATA_CAP_GB" 'BEGIN{printf "%.0f", gb * 1073741824}')
        if [ "$total_used" -ge "$cap_bytes" ] 2>/dev/null; then
            echo -e "${RED}⚠ Data cap exceeded ($(format_gb $total_used) / ${DATA_CAP_GB} GB). Containers will not restart.${NC}"
            echo -e "${YELLOW}Reset or increase the data cap from the menu to restart containers.${NC}"
            return 1
        fi
    fi

    echo "Restarting Conduit ($CONTAINER_COUNT container(s))..."
    local any_found=false
    for i in $(seq 1 $CONTAINER_COUNT); do
        local name=$(get_container_name $i)
        local vol=$(get_volume_name $i)
        if docker ps -a 2>/dev/null | grep -q "[[:space:]]${name}$"; then
            any_found=true
            docker stop "$name" 2>/dev/null || true
            docker rm "$name" 2>/dev/null || true
        fi
        docker volume create "$vol" 2>/dev/null || true
        fix_volume_permissions $i
        run_conduit_container $i
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ ${name} restarted${NC}"
        else
            echo -e "${RED}✗ Failed to restart ${name}${NC}"
        fi
    done
    # Remove extra containers beyond current count
    for i in $(seq $((CONTAINER_COUNT + 1)) 5); do
        local name=$(get_container_name $i)
        if docker ps -a 2>/dev/null | grep -q "[[:space:]]${name}$"; then
            docker stop "$name" 2>/dev/null || true
            docker rm "$name" 2>/dev/null || true
            echo -e "${YELLOW}✓ ${name} removed (scaled down)${NC}"
        fi
    done
    # Backup tracker data before regenerating
    local persist_dir="$INSTALL_DIR/traffic_stats"
    if [ -s "$persist_dir/cumulative_data" ] || [ -s "$persist_dir/cumulative_ips" ]; then
        echo -e "${CYAN}⟳ Saving tracker data snapshot...${NC}"
        [ -s "$persist_dir/cumulative_data" ] && cp "$persist_dir/cumulative_data" "$persist_dir/cumulative_data.bak"
        [ -s "$persist_dir/cumulative_ips" ] && cp "$persist_dir/cumulative_ips" "$persist_dir/cumulative_ips.bak"
        [ -s "$persist_dir/geoip_cache" ] && cp "$persist_dir/geoip_cache" "$persist_dir/geoip_cache.bak"
        echo -e "${GREEN}✓ Tracker data snapshot saved${NC}"
    fi
    # Regenerate tracker script and restart tracker service
    regenerate_tracker_script
    if command -v systemctl &>/dev/null && systemctl is-active --quiet conduit-tracker.service 2>/dev/null; then
        systemctl restart conduit-tracker.service 2>/dev/null || true
    fi
}

