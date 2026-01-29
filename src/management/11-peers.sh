show_peers() {
    local stop_peers=0
    trap 'stop_peers=1' SIGINT SIGTERM

    local persist_dir="$INSTALL_DIR/traffic_stats"

    # Ensure tracker is running
    if ! is_tracker_active; then
        setup_tracker_service 2>/dev/null || true
    fi

    tput smcup 2>/dev/null || true
    echo -ne "\033[?25l"
    printf "\033[2J\033[H"

    local EL="\033[K"
    local cycle_start=$(date +%s)
    local last_refresh=0

    while [ $stop_peers -eq 0 ]; do
        local now=$(date +%s)
        local term_height=$(stty size </dev/tty 2>/dev/null | awk '{print $1}')
        [ -z "$term_height" ] || [ "$term_height" -lt 10 ] 2>/dev/null && term_height=$(tput lines 2>/dev/null || echo "${LINES:-24}")
        local cycle_elapsed=$(( (now - cycle_start) % 15 ))
        local time_left=$((15 - cycle_elapsed))

        # Progress bar
        local bar=""
        for ((i=0; i<cycle_elapsed; i++)); do bar+="●"; done
        for ((i=cycle_elapsed; i<15; i++)); do bar+="○"; done

        # Refresh data every 15 seconds or first run
        if [ $((now - last_refresh)) -ge 15 ] || [ "$last_refresh" -eq 0 ]; then
            last_refresh=$now
            cycle_start=$now

            printf "\033[H"

            echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}${EL}"
            echo -e "${CYAN}║${NC}  ${BOLD}LIVE PEER TRAFFIC BY COUNTRY${NC}                     ${DIM}[q] Back${NC}  ${EL}"
            echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}${EL}"
            printf "${CYAN}║${NC} Last Update: %-42s ${GREEN}[LIVE]${NC}${EL}\n" "$(date +%H:%M:%S)"
            echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}${EL}"
            echo -e "${EL}"

            # Load tracker data
            unset cumul_from cumul_to total_ips_count 2>/dev/null
            declare -A cumul_from cumul_to total_ips_count

            local grand_in=0 grand_out=0

            if [ -s "$persist_dir/cumulative_data" ]; then
                while IFS='|' read -r c f t; do
                    [ -z "$c" ] && continue
                    [[ "$c" == *"can't"* || "$c" == *"error"* ]] && continue
                    f=$(printf '%.0f' "${f:-0}" 2>/dev/null) || f=0
                    t=$(printf '%.0f' "${t:-0}" 2>/dev/null) || t=0
                    cumul_from["$c"]=$f
                    cumul_to["$c"]=$t
                    grand_in=$((grand_in + f))
                    grand_out=$((grand_out + t))
                done < "$persist_dir/cumulative_data"
            fi

            if [ -s "$persist_dir/cumulative_ips" ]; then
                while IFS='|' read -r c ip; do
                    [ -z "$c" ] && continue
                    [[ "$c" == *"can't"* || "$c" == *"error"* ]] && continue
                    total_ips_count["$c"]=$((${total_ips_count["$c"]:-0} + 1))
                done < "$persist_dir/cumulative_ips"
            fi

            # Get actual connected clients from docker logs
            local total_clients=0
            local docker_ps_cache=$(docker ps --format '{{.Names}}' 2>/dev/null)
            for ci in $(seq 1 $CONTAINER_COUNT); do
                local cname=$(get_container_name $ci)
                if echo "$docker_ps_cache" | grep -q "^${cname}$"; then
                    local logs=$(docker logs --tail 50 "$cname" 2>&1 | grep "\[STATS\]" | tail -1)
                    local conn=$(echo "$logs" | sed -n 's/.*Connected:[[:space:]]*\([0-9]*\).*/\1/p')
                    [[ "$conn" =~ ^[0-9]+$ ]] && total_clients=$((total_clients + conn))
                fi
            done

            echo -e "${EL}"

            # Parse snapshot for speed and country distribution
            unset snap_from_bytes snap_to_bytes snap_from_ips snap_to_ips 2>/dev/null
            declare -A snap_from_bytes snap_to_bytes snap_from_ips snap_to_ips
            local snap_total_from_ips=0 snap_total_to_ips=0
            if [ -s "$persist_dir/tracker_snapshot" ]; then
                while IFS='|' read -r dir c bytes ip; do
                    [ -z "$c" ] && continue
                    [[ "$c" == *"can't"* || "$c" == *"error"* ]] && continue
                    bytes=$(printf '%.0f' "${bytes:-0}" 2>/dev/null) || bytes=0
                    if [ "$dir" = "FROM" ]; then
                        snap_from_bytes["$c"]=$(( ${snap_from_bytes["$c"]:-0} + bytes ))
                        snap_from_ips["$c|$ip"]=1
                    elif [ "$dir" = "TO" ]; then
                        snap_to_bytes["$c"]=$(( ${snap_to_bytes["$c"]:-0} + bytes ))
                        snap_to_ips["$c|$ip"]=1
                    fi
                done < "$persist_dir/tracker_snapshot"
            fi

            # Count unique snapshot IPs per country + totals
            unset snap_from_ip_cnt snap_to_ip_cnt 2>/dev/null
            declare -A snap_from_ip_cnt snap_to_ip_cnt
            for k in "${!snap_from_ips[@]}"; do
                local sc="${k%%|*}"
                snap_from_ip_cnt["$sc"]=$(( ${snap_from_ip_cnt["$sc"]:-0} + 1 ))
                snap_total_from_ips=$((snap_total_from_ips + 1))
            done
            for k in "${!snap_to_ips[@]}"; do
                local sc="${k%%|*}"
                snap_to_ip_cnt["$sc"]=$(( ${snap_to_ip_cnt["$sc"]:-0} + 1 ))
                snap_total_to_ips=$((snap_total_to_ips + 1))
            done

            # TOP 10 TRAFFIC FROM (peers connecting to you)
            echo -e "${GREEN}${BOLD} 📥 TOP 10 TRAFFIC FROM ${NC}${DIM}(peers connecting to you)${NC}${EL}"
            echo -e "${EL}"
            printf " ${BOLD}%-26s %10s %12s  %-12s${NC}${EL}\n" "Country" "Total" "Speed" "IPs / Clients"
            echo -e "${EL}"
            if [ "$grand_in" -gt 0 ]; then
                while IFS='|' read -r bytes country; do
                    [ -z "$country" ] && continue
                    local snap_b=${snap_from_bytes[$country]:-0}
                    local speed_val=$((snap_b / 15))
                    local speed_str=$(format_bytes $speed_val)
                    local ips_all=${total_ips_count[$country]:-0}
                    # Estimate clients per country using snapshot distribution
                    local snap_cnt=${snap_from_ip_cnt[$country]:-0}
                    local est_clients=0
                    if [ "$snap_total_from_ips" -gt 0 ] && [ "$snap_cnt" -gt 0 ]; then
                        est_clients=$(( (snap_cnt * total_clients) / snap_total_from_ips ))
                        [ "$est_clients" -eq 0 ] && [ "$snap_cnt" -gt 0 ] && est_clients=1
                    fi
                    printf " ${GREEN}%-26.26s${NC} %10s %10s/s  %5d/%d${EL}\n" "$country" "$(format_bytes $bytes)" "$speed_str" "$ips_all" "$est_clients"
                done < <(for c in "${!cumul_from[@]}"; do echo "${cumul_from[$c]:-0}|$c"; done | sort -t'|' -k1 -nr | head -10)
            else
                echo -e " ${DIM}Waiting for data...${NC}${EL}"
            fi
            echo -e "${EL}"

            # TOP 10 TRAFFIC TO (data sent to peers)
            echo -e "${YELLOW}${BOLD} 📤 TOP 10 TRAFFIC TO ${NC}${DIM}(data sent to peers)${NC}${EL}"
            echo -e "${EL}"
            printf " ${BOLD}%-26s %10s %12s  %-12s${NC}${EL}\n" "Country" "Total" "Speed" "IPs / Clients"
            echo -e "${EL}"
            if [ "$grand_out" -gt 0 ]; then
                while IFS='|' read -r bytes country; do
                    [ -z "$country" ] && continue
                    local snap_b=${snap_to_bytes[$country]:-0}
                    local speed_val=$((snap_b / 15))
                    local speed_str=$(format_bytes $speed_val)
                    local ips_all=${total_ips_count[$country]:-0}
                    local snap_cnt=${snap_to_ip_cnt[$country]:-0}
                    local est_clients=0
                    if [ "$snap_total_to_ips" -gt 0 ] && [ "$snap_cnt" -gt 0 ]; then
                        est_clients=$(( (snap_cnt * total_clients) / snap_total_to_ips ))
                        [ "$est_clients" -eq 0 ] && [ "$snap_cnt" -gt 0 ] && est_clients=1
                    fi
                    printf " ${YELLOW}%-26.26s${NC} %10s %10s/s  %5d/%d${EL}\n" "$country" "$(format_bytes $bytes)" "$speed_str" "$ips_all" "$est_clients"
                done < <(for c in "${!cumul_to[@]}"; do echo "${cumul_to[$c]:-0}|$c"; done | sort -t'|' -k1 -nr | head -10)
            else
                echo -e " ${DIM}Waiting for data...${NC}${EL}"
            fi

            echo -e "${EL}"
            printf "\033[J"
        fi

        # Progress bar at bottom
        printf "\033[${term_height};1H${EL}"
        printf "[${YELLOW}${bar}${NC}] Next refresh in %2ds  ${DIM}[q] Back${NC}" "$time_left"

        if read -t 1 -n 1 -s key < /dev/tty 2>/dev/null; then
            case "$key" in q|Q) stop_peers=1 ;; esac
        fi
    done
    echo -ne "\033[?25h"
    tput rmcup 2>/dev/null || true
    rm -f /tmp/conduit_peers_sorted
    trap - SIGINT SIGTERM
}

get_net_speed() {
    # Calculate System Network Speed (Active 0.5s Sample)
    # Returns: "RX_MBPS TX_MBPS"
    local iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5}')
    [ -z "$iface" ] && iface=$(ip route list default 2>/dev/null | awk '{print $5}')
    
    if [ -n "$iface" ] && [ -f "/sys/class/net/$iface/statistics/rx_bytes" ]; then
        local rx1=$(cat /sys/class/net/$iface/statistics/rx_bytes)
        local tx1=$(cat /sys/class/net/$iface/statistics/tx_bytes)
        
        sleep 0.5
        
        local rx2=$(cat /sys/class/net/$iface/statistics/rx_bytes)
        local tx2=$(cat /sys/class/net/$iface/statistics/tx_bytes)
        
        # Calculate Delta (Bytes)
        local rx_delta=$((rx2 - rx1))
        local tx_delta=$((tx2 - tx1))
        
        # Convert to Mbps: (bytes * 8 bits) / (0.5 sec * 1,000,000)
        # Formula simplified: bytes * 16 / 1000000
        
        local rx_mbps=$(awk -v b="$rx_delta" 'BEGIN { printf "%.2f", (b * 16) / 1000000 }')
        local tx_mbps=$(awk -v b="$tx_delta" 'BEGIN { printf "%.2f", (b * 16) / 1000000 }')
        
        echo "$rx_mbps $tx_mbps"
    else
        echo "0.00 0.00"
    fi
}

