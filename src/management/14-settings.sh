change_settings() {
    echo ""
    echo -e "${CYAN}═══ Current Settings ═══${NC}"
    echo ""
    printf "  ${BOLD}%-12s %-12s %-12s${NC}\n" "Container" "Max Clients" "Bandwidth"
    echo -e "  ${CYAN}────────────────────────────────────────${NC}"
    for i in $(seq 1 $CONTAINER_COUNT); do
        local cname=$(get_container_name $i)
        local mc=$(get_container_max_clients $i)
        local bw=$(get_container_bandwidth $i)
        local bw_display="Unlimited"
        [ "$bw" != "-1" ] && bw_display="${bw} Mbps"
        printf "  %-12s %-12s %-12s\n" "$cname" "$mc" "$bw_display"
    done
    echo ""
    echo -e "  Default: Max Clients=${GREEN}${MAX_CLIENTS}${NC}  Bandwidth=${GREEN}$([ "$BANDWIDTH" = "-1" ] && echo "Unlimited" || echo "${BANDWIDTH} Mbps")${NC}"
    echo ""

    # Select target
    echo -e "  ${BOLD}Apply settings to:${NC}"
    echo -e "  ${GREEN}a${NC}) All containers (set same values)"
    for i in $(seq 1 $CONTAINER_COUNT); do
        echo -e "  ${GREEN}${i}${NC}) $(get_container_name $i)"
    done
    echo ""
    read -p "  Select (a/1-${CONTAINER_COUNT}): " target < /dev/tty || true

    local targets=()
    if [ "$target" = "a" ] || [ "$target" = "A" ]; then
        for i in $(seq 1 $CONTAINER_COUNT); do targets+=($i); done
    elif [[ "$target" =~ ^[0-9]+$ ]] && [ "$target" -ge 1 ] && [ "$target" -le "$CONTAINER_COUNT" ]; then
        targets+=($target)
    else
        echo -e "  ${RED}Invalid selection.${NC}"
        return
    fi

    # Get new values
    local cur_mc=$(get_container_max_clients ${targets[0]})
    local cur_bw=$(get_container_bandwidth ${targets[0]})
    echo ""
    read -p "  New max-clients (1-1000) [${cur_mc}]: " new_clients < /dev/tty || true

    echo ""
    local cur_bw_display="Unlimited"
    [ "$cur_bw" != "-1" ] && cur_bw_display="${cur_bw} Mbps"
    echo "  Current bandwidth: ${cur_bw_display}"
    read -p "  Set unlimited bandwidth? [y/N]: " set_unlimited < /dev/tty || true

    local new_bandwidth=""
    if [[ "$set_unlimited" =~ ^[Yy]$ ]]; then
        new_bandwidth="-1"
    else
        read -p "  New bandwidth in Mbps (1-40) [${cur_bw}]: " input_bw < /dev/tty || true
        [ -n "$input_bw" ] && new_bandwidth="$input_bw"
    fi

    # Validate max-clients
    local valid_mc=""
    if [ -n "$new_clients" ]; then
        if [[ "$new_clients" =~ ^[0-9]+$ ]] && [ "$new_clients" -ge 1 ] && [ "$new_clients" -le 1000 ]; then
            valid_mc="$new_clients"
        else
            echo -e "  ${YELLOW}Invalid max-clients. Keeping current.${NC}"
        fi
    fi

    # Validate bandwidth
    local valid_bw=""
    if [ -n "$new_bandwidth" ]; then
        if [ "$new_bandwidth" = "-1" ]; then
            valid_bw="-1"
        elif [[ "$new_bandwidth" =~ ^[0-9]+$ ]] && [ "$new_bandwidth" -ge 1 ] && [ "$new_bandwidth" -le 40 ]; then
            valid_bw="$new_bandwidth"
        elif [[ "$new_bandwidth" =~ ^[0-9]*\.[0-9]+$ ]]; then
            local float_ok=$(awk -v val="$new_bandwidth" 'BEGIN { print (val >= 1 && val <= 40) ? "yes" : "no" }')
            [ "$float_ok" = "yes" ] && valid_bw="$new_bandwidth" || echo -e "  ${YELLOW}Invalid bandwidth. Keeping current.${NC}"
        else
            echo -e "  ${YELLOW}Invalid bandwidth. Keeping current.${NC}"
        fi
    fi

    # Apply to targets
    if [ "$target" = "a" ] || [ "$target" = "A" ]; then
        # Apply to all = update global defaults and clear per-container overrides
        [ -n "$valid_mc" ] && MAX_CLIENTS="$valid_mc"
        [ -n "$valid_bw" ] && BANDWIDTH="$valid_bw"
        for i in $(seq 1 5); do
            unset "MAX_CLIENTS_${i}" 2>/dev/null || true
            unset "BANDWIDTH_${i}" 2>/dev/null || true
        done
    else
        # Apply to specific container
        local idx=${targets[0]}
        if [ -n "$valid_mc" ]; then
            eval "MAX_CLIENTS_${idx}=${valid_mc}"
        fi
        if [ -n "$valid_bw" ]; then
            eval "BANDWIDTH_${idx}=${valid_bw}"
        fi
    fi

    save_settings

    # Recreate affected containers
    echo ""
    echo "  Recreating container(s) with new settings..."
    for i in "${targets[@]}"; do
        local name=$(get_container_name $i)
        docker rm -f "$name" 2>/dev/null || true
    done
    sleep 1
    for i in "${targets[@]}"; do
        local name=$(get_container_name $i)
        fix_volume_permissions $i
        run_conduit_container $i
        if [ $? -eq 0 ]; then
            local mc=$(get_container_max_clients $i)
            local bw=$(get_container_bandwidth $i)
            local bw_d="Unlimited"
            [ "$bw" != "-1" ] && bw_d="${bw} Mbps"
            echo -e "  ${GREEN}✓ ${name}${NC} — clients: ${mc}, bandwidth: ${bw_d}"
        else
            echo -e "  ${RED}✗ Failed to restart ${name}${NC}"
        fi
    done
}

#═══════════════════════════════════════════════════════════════════════
# show_logs() - Display color-coded Docker logs
#═══════════════════════════════════════════════════════════════════════
# Colors log entries based on their type:
#   [OK]     - Green   (successful operations)
#   [INFO]   - Cyan    (informational messages)
#   [STATS]  - Blue    (statistics)
#   [WARN]   - Yellow  (warnings)
#   [ERROR]  - Red     (errors)
#   [DEBUG]  - Gray    (debug messages)
#═══════════════════════════════════════════════════════════════════════
