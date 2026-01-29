show_status() {
    local mode="${1:-normal}" # 'live' mode adds line clearing
    local EL=""
    if [ "$mode" == "live" ]; then
        EL="\033[K" # Erase Line escape code
    fi

    echo ""

    
    # Cache docker ps output once
    local docker_ps_cache=$(docker ps 2>/dev/null)

    # Count running containers and cache per-container stats
    local running_count=0
    declare -A _c_running _c_conn _c_cing _c_up _c_down
    local total_connecting=0
    local total_connected=0
    local uptime=""

    for i in $(seq 1 $CONTAINER_COUNT); do
        local cname=$(get_container_name $i)
        _c_running[$i]=false
        _c_conn[$i]="0"
        _c_cing[$i]="0"
        _c_up[$i]=""
        _c_down[$i]=""

        if echo "$docker_ps_cache" | grep -q "[[:space:]]${cname}$"; then
            _c_running[$i]=true
            running_count=$((running_count + 1))
            local logs=$(docker logs --tail 50 "$cname" 2>&1 | grep "STATS" | tail -1)
            if [ -n "$logs" ]; then
                # Single awk to extract all 5 fields, pipe-delimited
                IFS='|' read -r c_connecting c_connected c_up_val c_down_val c_uptime_val <<< $(echo "$logs" | awk '{
                    cing=0; conn=0; up=""; down=""; ut=""
                    for(j=1;j<=NF;j++){
                        if($j=="Connecting:") cing=$(j+1)+0
                        else if($j=="Connected:") conn=$(j+1)+0
                        else if($j=="Up:"){for(k=j+1;k<=NF;k++){if($k=="|"||$k~/Down:/)break; up=up (up?" ":"") $k}}
                        else if($j=="Down:"){for(k=j+1;k<=NF;k++){if($k=="|"||$k~/Uptime:/)break; down=down (down?" ":"") $k}}
                        else if($j=="Uptime:"){for(k=j+1;k<=NF;k++){ut=ut (ut?" ":"") $k}}
                    }
                    printf "%d|%d|%s|%s|%s", cing, conn, up, down, ut
                }')
                _c_conn[$i]="${c_connected:-0}"
                _c_cing[$i]="${c_connecting:-0}"
                _c_up[$i]="${c_up_val}"
                _c_down[$i]="${c_down_val}"
                total_connecting=$((total_connecting + ${c_connecting:-0}))
                total_connected=$((total_connected + ${c_connected:-0}))
                if [ -z "$uptime" ]; then
                    uptime="${c_uptime_val}"
                fi
            fi
        fi
    done
    local connecting=$total_connecting
    local connected=$total_connected
    # Export for parent function to reuse (avoids duplicate docker logs calls)
    _total_connected=$total_connected

    # Aggregate upload/download across all containers
    local upload=""
    local download=""
    local total_up_bytes=0
    local total_down_bytes=0
    for i in $(seq 1 $CONTAINER_COUNT); do
        if [ -n "${_c_up[$i]}" ]; then
            local bytes=$(echo "${_c_up[$i]}" | awk '{
                val=$1; unit=toupper($2)
                if (unit ~ /^KB/) val*=1024
                else if (unit ~ /^MB/) val*=1048576
                else if (unit ~ /^GB/) val*=1073741824
                else if (unit ~ /^TB/) val*=1099511627776
                printf "%.0f", val
            }')
            total_up_bytes=$((total_up_bytes + ${bytes:-0}))
        fi
        if [ -n "${_c_down[$i]}" ]; then
            local bytes=$(echo "${_c_down[$i]}" | awk '{
                val=$1; unit=toupper($2)
                if (unit ~ /^KB/) val*=1024
                else if (unit ~ /^MB/) val*=1048576
                else if (unit ~ /^GB/) val*=1073741824
                else if (unit ~ /^TB/) val*=1099511627776
                printf "%.0f", val
            }')
            total_down_bytes=$((total_down_bytes + ${bytes:-0}))
        fi
    done
    if [ "$total_up_bytes" -gt 0 ]; then
        upload=$(awk -v b="$total_up_bytes" 'BEGIN {
            if (b >= 1099511627776) printf "%.2f TB", b/1099511627776
            else if (b >= 1073741824) printf "%.2f GB", b/1073741824
            else if (b >= 1048576) printf "%.2f MB", b/1048576
            else if (b >= 1024) printf "%.2f KB", b/1024
            else printf "%d B", b
        }')
    fi
    if [ "$total_down_bytes" -gt 0 ]; then
        download=$(awk -v b="$total_down_bytes" 'BEGIN {
            if (b >= 1099511627776) printf "%.2f TB", b/1099511627776
            else if (b >= 1073741824) printf "%.2f GB", b/1073741824
            else if (b >= 1048576) printf "%.2f MB", b/1048576
            else if (b >= 1024) printf "%.2f KB", b/1024
            else printf "%d B", b
        }')
    fi

    if [ "$running_count" -gt 0 ]; then
        
        # Get Resource Stats
        local stats=$(get_container_stats)
        
        # Normalize App CPU (Docker % / Cores)
        local raw_app_cpu=$(echo "$stats" | awk '{print $1}' | tr -d '%')
        local num_cores=$(get_cpu_cores)
        local app_cpu="0%"
        local app_cpu_display=""
        
        if [[ "$raw_app_cpu" =~ ^[0-9.]+$ ]]; then
             # Use awk for floating point math
             app_cpu=$(awk -v cpu="$raw_app_cpu" -v cores="$num_cores" 'BEGIN {printf "%.2f%%", cpu / cores}')
             if [ "$num_cores" -gt 1 ]; then
                 app_cpu_display="${app_cpu} (${raw_app_cpu}% vCPU)"
             else
                 app_cpu_display="${app_cpu}"
             fi
        else
             app_cpu="${raw_app_cpu}%"
             app_cpu_display="${app_cpu}"
        fi
        
        # Keep full "Used / Limit" string for App RAM
        local app_ram=$(echo "$stats" | awk '{print $2, $3, $4}') 
        
        local sys_stats=$(get_system_stats)
        local sys_cpu=$(echo "$sys_stats" | awk '{print $1}')
        local sys_ram_used=$(echo "$sys_stats" | awk '{print $2}')
        local sys_ram_total=$(echo "$sys_stats" | awk '{print $3}')
        local sys_ram_pct=$(echo "$sys_stats" | awk '{print $4}')

        # New Metric: Network Speed (System Wide)
        local net_speed=$(get_net_speed)
        local rx_mbps=$(echo "$net_speed" | awk '{print $1}')
        local tx_mbps=$(echo "$net_speed" | awk '{print $2}')
        local net_display="↓ ${rx_mbps} Mbps  ↑ ${tx_mbps} Mbps"
        
        if [ -n "$upload" ] || [ "$connected" -gt 0 ] || [ "$connecting" -gt 0 ]; then
            local status_line="${BOLD}Status:${NC} ${GREEN}Running${NC}"
            [ -n "$uptime" ] && status_line="${status_line} (${uptime})"
            echo -e "${status_line}${EL}"
            echo -e "  Containers: ${GREEN}${running_count}${NC}/${CONTAINER_COUNT}    Clients: ${GREEN}${connected}${NC} connected, ${YELLOW}${connecting}${NC} connecting${EL}"

            echo -e "${EL}"
            echo -e "${CYAN}═══ Traffic ═══${NC}${EL}"
            [ -n "$upload" ] && echo -e "  Upload:       ${CYAN}${upload}${NC}${EL}"
            [ -n "$download" ] && echo -e "  Download:     ${CYAN}${download}${NC}${EL}"

            echo -e "${EL}"
            echo -e "${CYAN}═══ Resource Usage ═══${NC}${EL}"
            printf "  %-8s CPU: ${YELLOW}%-20s${NC} | RAM: ${YELLOW}%-20s${NC}${EL}\n" "App:" "$app_cpu_display" "$app_ram"
            printf "  %-8s CPU: ${YELLOW}%-20s${NC} | RAM: ${YELLOW}%-20s${NC}${EL}\n" "System:" "$sys_cpu" "$sys_ram_used / $sys_ram_total"
            printf "  %-8s Net: ${YELLOW}%-43s${NC}${EL}\n" "Total:" "$net_display"


        else
             echo -e "${BOLD}Status:${NC} ${GREEN}Running${NC}${EL}"
             echo -e "  Containers: ${GREEN}${running_count}${NC}/${CONTAINER_COUNT}${EL}"
             echo -e "${EL}"
             echo -e "${CYAN}═══ Resource Usage ═══${NC}${EL}"
             printf "  %-8s CPU: ${YELLOW}%-20s${NC} | RAM: ${YELLOW}%-20s${NC}${EL}\n" "App:" "$app_cpu_display" "$app_ram"
             printf "  %-8s CPU: ${YELLOW}%-20s${NC} | RAM: ${YELLOW}%-20s${NC}${EL}\n" "System:" "$sys_cpu" "$sys_ram_used / $sys_ram_total"
             printf "  %-8s Net: ${YELLOW}%-43s${NC}${EL}\n" "Total:" "$net_display"
             echo -e "${EL}"
             echo -e "  Stats:        ${YELLOW}Waiting for first stats...${NC}${EL}"
        fi
        
    else
        echo -e "${BOLD}Status:${NC} ${RED}Stopped${NC}${EL}"
    fi
    

    
    echo -e "${EL}"
    echo -e "${CYAN}═══ SETTINGS ═══${NC}${EL}"
    # Check if any per-container overrides exist
    local has_overrides=false
    for i in $(seq 1 $CONTAINER_COUNT); do
        local mc_var="MAX_CLIENTS_${i}"
        local bw_var="BANDWIDTH_${i}"
        if [ -n "${!mc_var}" ] || [ -n "${!bw_var}" ]; then
            has_overrides=true
            break
        fi
    done
    if [ "$has_overrides" = true ]; then
        echo -e "  Containers:   ${CONTAINER_COUNT}${EL}"
        for i in $(seq 1 $CONTAINER_COUNT); do
            local mc=$(get_container_max_clients $i)
            local bw=$(get_container_bandwidth $i)
            local bw_d="Unlimited"
            [ "$bw" != "-1" ] && bw_d="${bw} Mbps"
            printf "  %-12s clients: %-5s bw: %s${EL}\n" "$(get_container_name $i)" "$mc" "$bw_d"
        done
    else
        echo -e "  Max Clients:  ${MAX_CLIENTS}${EL}"
        if [ "$BANDWIDTH" == "-1" ]; then
            echo -e "  Bandwidth:    Unlimited${EL}"
        else
            echo -e "  Bandwidth:    ${BANDWIDTH} Mbps${EL}"
        fi
        echo -e "  Containers:   ${CONTAINER_COUNT}${EL}"
    fi
    if [ "$DATA_CAP_GB" -gt 0 ] 2>/dev/null; then
        local usage=$(get_data_usage)
        local used_rx=$(echo "$usage" | awk '{print $1}')
        local used_tx=$(echo "$usage" | awk '{print $2}')
        local total_used=$((used_rx + used_tx + ${DATA_CAP_PRIOR_USAGE:-0}))
        echo -e "  Data Cap:     $(format_gb $total_used) / ${DATA_CAP_GB} GB${EL}"
    fi

    
    echo -e "${EL}"
    echo -e "${CYAN}═══ AUTO-START SERVICE ═══${NC}${EL}"
    # Check for systemd
    if command -v systemctl &>/dev/null && systemctl is-enabled conduit.service 2>/dev/null | grep -q "enabled"; then
        echo -e "  Auto-start:   ${GREEN}Enabled (systemd)${NC}${EL}"
        local svc_status=$(systemctl is-active conduit.service 2>/dev/null)
        echo -e "  Service:      ${svc_status:-unknown}${EL}"
    # Check for OpenRC
    elif command -v rc-status &>/dev/null && rc-status -a 2>/dev/null | grep -q "conduit"; then
        echo -e "  Auto-start:   ${GREEN}Enabled (OpenRC)${NC}${EL}"
    # Check for SysVinit
    elif [ -f /etc/init.d/conduit ]; then
        echo -e "  Auto-start:   ${GREEN}Enabled (SysVinit)${NC}${EL}"
    else
        echo -e "  Auto-start:   ${YELLOW}Not configured${NC}${EL}"
        echo -e "  Note:         Docker restart policy handles restarts${EL}"
    fi
    # Check Background Tracker
    if is_tracker_active; then
        echo -e "  Tracker:      ${GREEN}Active${NC}${EL}"
    else
        echo -e "  Tracker:      ${YELLOW}Inactive${NC}${EL}"
    fi
    echo -e "${EL}"
}

