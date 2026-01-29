show_advanced_stats() {
    local persist_dir="$INSTALL_DIR/traffic_stats"
    local exit_stats=0
    trap 'exit_stats=1' SIGINT SIGTERM

    local L="══════════════════════════════════════════════════════════════"
    local D="──────────────────────────────────────────────────────────────"

    # Enter alternate screen buffer
    tput smcup 2>/dev/null || true
    echo -ne "\033[?25l"
    printf "\033[2J\033[H"

    local cycle_start=$(date +%s)
    local last_refresh=0

    while [ "$exit_stats" -eq 0 ]; do
        local now=$(date +%s)
        local term_height=$(stty size </dev/tty 2>/dev/null | awk '{print $1}')
        [ -z "$term_height" ] || [ "$term_height" -lt 10 ] 2>/dev/null && term_height=$(tput lines 2>/dev/null || echo "${LINES:-24}")

        local cycle_elapsed=$(( (now - cycle_start) % 15 ))
        local time_until_next=$((15 - cycle_elapsed))

        # Build progress bar
        local bar=""
        for ((i=0; i<cycle_elapsed; i++)); do bar+="●"; done
        for ((i=cycle_elapsed; i<15; i++)); do bar+="○"; done

        # Refresh data every 15 seconds or first run
        if [ $((now - last_refresh)) -ge 15 ] || [ "$last_refresh" -eq 0 ]; then
            last_refresh=$now
            cycle_start=$now

            printf "\033[H"

            echo -e "${CYAN}╔${L}${NC}\033[K"
            echo -e "${CYAN}║${NC}  ${BOLD}ADVANCED STATISTICS${NC}        ${DIM}[q] Back  Auto-refresh${NC}\033[K"
            echo -e "${CYAN}╠${L}${NC}\033[K"

            # Container stats - aggregate from all containers
            local docker_ps_cache=$(docker ps --format '{{.Names}}' 2>/dev/null)
            local container_count=0
            local total_cpu=0 total_conn=0
            local total_up_bytes=0 total_down_bytes=0
            local total_mem_mib=0 first_mem_limit=""

            echo -e "${CYAN}║${NC} ${GREEN}CONTAINER${NC}  ${DIM}|${NC}  ${YELLOW}NETWORK${NC}  ${DIM}|${NC}  ${MAGENTA}TRACKER${NC}\033[K"

            # Single docker stats call for all running containers
            local adv_running_names=""
            for ci in $(seq 1 $CONTAINER_COUNT); do
                local cname=$(get_container_name $ci)
                echo "$docker_ps_cache" | grep -q "^${cname}$" && adv_running_names+=" $cname"
            done
            local adv_all_stats=""
            if [ -n "$adv_running_names" ]; then
                adv_all_stats=$(docker stats --no-stream --format "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}" $adv_running_names 2>/dev/null)
            fi

            for ci in $(seq 1 $CONTAINER_COUNT); do
                local cname=$(get_container_name $ci)
                if echo "$docker_ps_cache" | grep -q "^${cname}$"; then
                    container_count=$((container_count + 1))

                    local stats=$(echo "$adv_all_stats" | grep "^${cname}|" 2>/dev/null)
                    local cpu=$(echo "$stats" | cut -d'|' -f2 | tr -d '%')
                    [[ "$cpu" =~ ^[0-9.]+$ ]] && total_cpu=$(awk -v a="$total_cpu" -v b="$cpu" 'BEGIN{printf "%.2f", a+b}')

                    local cmem_str=$(echo "$stats" | cut -d'|' -f3 | awk '{print $1}')
                    local cmem_val=$(echo "$cmem_str" | sed 's/[^0-9.]//g')
                    local cmem_unit=$(echo "$cmem_str" | sed 's/[0-9.]//g')
                    if [[ "$cmem_val" =~ ^[0-9.]+$ ]]; then
                        case "$cmem_unit" in
                            GiB) cmem_val=$(awk -v v="$cmem_val" 'BEGIN{printf "%.2f", v*1024}') ;;
                            KiB) cmem_val=$(awk -v v="$cmem_val" 'BEGIN{printf "%.2f", v/1024}') ;;
                        esac
                        total_mem_mib=$(awk -v a="$total_mem_mib" -v b="$cmem_val" 'BEGIN{printf "%.2f", a+b}')
                    fi
                    [ -z "$first_mem_limit" ] && first_mem_limit=$(echo "$stats" | cut -d'|' -f3 | awk -F'/' '{print $2}' | xargs)

                    local logs=$(docker logs --tail 50 "$cname" 2>&1 | grep "\[STATS\]" | tail -1)
                    local conn=$(echo "$logs" | sed -n 's/.*Connected:[[:space:]]*\([0-9]*\).*/\1/p')
                    [[ "$conn" =~ ^[0-9]+$ ]] && total_conn=$((total_conn + conn))

                    # Parse upload/download to bytes
                    local up_raw=$(echo "$logs" | sed -n 's/.*Up:[[:space:]]*\([^|]*\).*/\1/p' | xargs)
                    local down_raw=$(echo "$logs" | sed -n 's/.*Down:[[:space:]]*\([^|]*\).*/\1/p' | xargs)
                    if [ -n "$up_raw" ]; then
                        local up_val=$(echo "$up_raw" | sed 's/[^0-9.]//g')
                        local up_unit=$(echo "$up_raw" | sed 's/[0-9. ]//g')
                        if [[ "$up_val" =~ ^[0-9.]+$ ]]; then
                            case "$up_unit" in
                                GB) total_up_bytes=$(awk -v a="$total_up_bytes" -v v="$up_val" 'BEGIN{printf "%.0f", a+v*1073741824}') ;;
                                MB) total_up_bytes=$(awk -v a="$total_up_bytes" -v v="$up_val" 'BEGIN{printf "%.0f", a+v*1048576}') ;;
                                KB) total_up_bytes=$(awk -v a="$total_up_bytes" -v v="$up_val" 'BEGIN{printf "%.0f", a+v*1024}') ;;
                                B)  total_up_bytes=$(awk -v a="$total_up_bytes" -v v="$up_val" 'BEGIN{printf "%.0f", a+v}') ;;
                            esac
                        fi
                    fi
                    if [ -n "$down_raw" ]; then
                        local down_val=$(echo "$down_raw" | sed 's/[^0-9.]//g')
                        local down_unit=$(echo "$down_raw" | sed 's/[0-9. ]//g')
                        if [[ "$down_val" =~ ^[0-9.]+$ ]]; then
                            case "$down_unit" in
                                GB) total_down_bytes=$(awk -v a="$total_down_bytes" -v v="$down_val" 'BEGIN{printf "%.0f", a+v*1073741824}') ;;
                                MB) total_down_bytes=$(awk -v a="$total_down_bytes" -v v="$down_val" 'BEGIN{printf "%.0f", a+v*1048576}') ;;
                                KB) total_down_bytes=$(awk -v a="$total_down_bytes" -v v="$down_val" 'BEGIN{printf "%.0f", a+v*1024}') ;;
                                B)  total_down_bytes=$(awk -v a="$total_down_bytes" -v v="$down_val" 'BEGIN{printf "%.0f", a+v}') ;;
                            esac
                        fi
                    fi
                fi
            done

            if [ "$container_count" -gt 0 ]; then
                local cpu_display="${total_cpu}%"
                [ "$container_count" -gt 1 ] && cpu_display="${total_cpu}% (${container_count} containers)"
                local mem_display="${total_mem_mib}MiB"
                if [ -n "$first_mem_limit" ] && [ "$container_count" -gt 1 ]; then
                    mem_display="${total_mem_mib}MiB (${container_count}x ${first_mem_limit})"
                elif [ -n "$first_mem_limit" ]; then
                    mem_display="${total_mem_mib}MiB / ${first_mem_limit}"
                fi
                printf "${CYAN}║${NC} CPU: ${YELLOW}%s${NC}  Mem: ${YELLOW}%s${NC}  Clients: ${GREEN}%d${NC}\033[K\n" "$cpu_display" "$mem_display" "$total_conn"
                local up_display=$(format_bytes "$total_up_bytes")
                local down_display=$(format_bytes "$total_down_bytes")
                printf "${CYAN}║${NC} Upload: ${GREEN}%s${NC}    Download: ${GREEN}%s${NC}\033[K\n" "$up_display" "$down_display"
            else
                echo -e "${CYAN}║${NC} ${RED}No Containers Running${NC}\033[K"
            fi

            # Network info
            local ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
            local iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
            printf "${CYAN}║${NC} Net: ${GREEN}%s${NC} (%s)\033[K\n" "${ip:-N/A}" "${iface:-?}"

            echo -e "${CYAN}╠${D}${NC}\033[K"

            # Load tracker data
            local total_active=0 total_in=0 total_out=0
            unset cips cbw_in cbw_out
            declare -A cips cbw_in cbw_out

            if [ -s "$persist_dir/cumulative_data" ]; then
                while IFS='|' read -r country from_bytes to_bytes; do
                    [ -z "$country" ] && continue
                    from_bytes=$(printf '%.0f' "${from_bytes:-0}" 2>/dev/null) || from_bytes=0
                    to_bytes=$(printf '%.0f' "${to_bytes:-0}" 2>/dev/null) || to_bytes=0
                    cbw_in["$country"]=$from_bytes
                    cbw_out["$country"]=$to_bytes
                    total_in=$((total_in + from_bytes))
                    total_out=$((total_out + to_bytes))
                done < "$persist_dir/cumulative_data"
            fi

            if [ -s "$persist_dir/cumulative_ips" ]; then
                while IFS='|' read -r country ip_addr; do
                    [ -z "$country" ] && continue
                    cips["$country"]=$((${cips["$country"]:-0} + 1))
                    total_active=$((total_active + 1))
                done < "$persist_dir/cumulative_ips"
            fi

            local tstat="${RED}Off${NC}"; is_tracker_active && tstat="${GREEN}On${NC}"
            printf "${CYAN}║${NC} Tracker: %b  Clients: ${GREEN}%d${NC}  Unique IPs: ${YELLOW}%d${NC}  In: ${GREEN}%s${NC}  Out: ${YELLOW}%s${NC}\033[K\n" "$tstat" "$total_conn" "$total_active" "$(format_bytes $total_in)" "$(format_bytes $total_out)"

            # TOP 5 by Unique IPs (from tracker)
            echo -e "${CYAN}╠─── ${CYAN}TOP 5 BY UNIQUE IPs${NC} ${DIM}(tracked)${NC}\033[K"
            local total_traffic=$((total_in + total_out))
            if [ "$total_conn" -gt 0 ] && [ "$total_active" -gt 0 ]; then
                for c in "${!cips[@]}"; do echo "${cips[$c]}|$c"; done | sort -t'|' -k1 -nr | head -7 | while IFS='|' read -r active_cnt country; do
                    local peers=$(( (active_cnt * total_conn) / total_active ))
                    [ "$peers" -eq 0 ] && [ "$active_cnt" -gt 0 ] && peers=1
                    local pct=$((peers * 100 / total_conn))
                    local blen=$((pct / 8)); [ "$blen" -lt 1 ] && blen=1; [ "$blen" -gt 14 ] && blen=14
                    local bfill=""; for ((i=0; i<blen; i++)); do bfill+="█"; done
                    printf "${CYAN}║${NC} %-16.16s %3d%% ${CYAN}%-14s${NC} (%d IPs)\033[K\n" "$country" "$pct" "$bfill" "$peers"
                done
            elif [ "$total_traffic" -gt 0 ]; then
                for c in "${!cbw_in[@]}"; do
                    local bytes=$(( ${cbw_in[$c]:-0} + ${cbw_out[$c]:-0} ))
                    echo "${bytes}|$c"
                done | sort -t'|' -k1 -nr | head -7 | while IFS='|' read -r bytes country; do
                    local pct=$((bytes * 100 / total_traffic))
                    local blen=$((pct / 8)); [ "$blen" -lt 1 ] && blen=1; [ "$blen" -gt 14 ] && blen=14
                    local bfill=""; for ((i=0; i<blen; i++)); do bfill+="█"; done
                    printf "${CYAN}║${NC} %-16.16s %3d%% ${CYAN}%-14s${NC} (%9s)\033[K\n" "$country" "$pct" "$bfill" "by traffic"
                done
            else
                echo -e "${CYAN}║${NC} No data yet\033[K"
            fi

            # TOP 5 by Download
            echo -e "${CYAN}╠─── ${GREEN}TOP 5 BY DOWNLOAD${NC} ${DIM}(inbound traffic)${NC}\033[K"
            if [ "$total_in" -gt 0 ]; then
                for c in "${!cbw_in[@]}"; do echo "${cbw_in[$c]}|$c"; done | sort -t'|' -k1 -nr | head -7 | while IFS='|' read -r bytes country; do
                    local pct=$((bytes * 100 / total_in))
                    local blen=$((pct / 8)); [ "$blen" -lt 1 ] && blen=1; [ "$blen" -gt 14 ] && blen=14
                    local bfill=""; for ((i=0; i<blen; i++)); do bfill+="█"; done
                    printf "${CYAN}║${NC} %-16.16s %3d%% ${GREEN}%-14s${NC} (%9s)\033[K\n" "$country" "$pct" "$bfill" "$(format_bytes $bytes)"
                done
            else
                echo -e "${CYAN}║${NC} No data yet\033[K"
            fi

            # TOP 5 by Upload
            echo -e "${CYAN}╠─── ${YELLOW}TOP 5 BY UPLOAD${NC} ${DIM}(outbound traffic)${NC}\033[K"
            if [ "$total_out" -gt 0 ]; then
                for c in "${!cbw_out[@]}"; do echo "${cbw_out[$c]}|$c"; done | sort -t'|' -k1 -nr | head -7 | while IFS='|' read -r bytes country; do
                    local pct=$((bytes * 100 / total_out))
                    local blen=$((pct / 8)); [ "$blen" -lt 1 ] && blen=1; [ "$blen" -gt 14 ] && blen=14
                    local bfill=""; for ((i=0; i<blen; i++)); do bfill+="█"; done
                    printf "${CYAN}║${NC} %-16.16s %3d%% ${YELLOW}%-14s${NC} (%9s)\033[K\n" "$country" "$pct" "$bfill" "$(format_bytes $bytes)"
                done
            else
                echo -e "${CYAN}║${NC} No data yet\033[K"
            fi

            echo -e "${CYAN}╚${L}${NC}\033[K"
            printf "\033[J"
        fi

        # Progress bar at bottom
        printf "\033[${term_height};1H\033[K"
        printf "[${YELLOW}${bar}${NC}] Next refresh in %2ds  ${DIM}[q] Back${NC}" "$time_until_next"

        if read -t 1 -n 1 -s key < /dev/tty 2>/dev/null; then
            case "$key" in
                q|Q) exit_stats=1 ;;
            esac
        fi
    done

    echo -ne "\033[?25h"
    tput rmcup 2>/dev/null || true
    trap - SIGINT SIGTERM
}

# show_peers() - Live peer traffic by country using tcpdump + GeoIP
