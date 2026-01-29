manage_containers() {
    local stop_manage=0
    trap 'stop_manage=1' SIGINT SIGTERM

    tput smcup 2>/dev/null || true
    echo -ne "\033[?25l"
    printf "\033[2J\033[H"

    local EL="\033[K"
    local need_input=true
    local mc_choice=""

    while [ $stop_manage -eq 0 ]; do
        # Soft update: cursor home, no clear
        printf "\033[H"

        echo -e "${EL}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}${EL}"
        echo -e "${CYAN}  MANAGE CONTAINERS${NC}    ${GREEN}${CONTAINER_COUNT}${NC}/5  Host networking${EL}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}${EL}"
        echo -e "${EL}"

        # Per-container stats table
        local docker_ps_cache=$(docker ps --format '{{.Names}}' 2>/dev/null)

        # Single docker stats call for all running containers (instead of per-container)
        local all_dstats=""
        local running_names=""
        for ci in $(seq 1 $CONTAINER_COUNT); do
            local cname=$(get_container_name $ci)
            if echo "$docker_ps_cache" | grep -q "^${cname}$"; then
                running_names+=" $cname"
            fi
        done
        if [ -n "$running_names" ]; then
            all_dstats=$(docker stats --no-stream --format "{{.Name}} {{.CPUPerc}} {{.MemUsage}}" $running_names 2>/dev/null)
        fi

        printf "  ${BOLD}%-2s %-11s %-8s %-7s %-8s %-8s %-6s %-7s${NC}${EL}\n" \
            "#" "Container" "Status" "Clients" "Up" "Down" "CPU" "RAM"
        echo -e "  ${CYAN}─────────────────────────────────────────────────────────${NC}${EL}"

        for ci in $(seq 1 5); do
            local cname=$(get_container_name $ci)
            local status_text status_color
            local c_clients="-" c_up="-" c_down="-" c_cpu="-" c_ram="-"

            if [ "$ci" -le "$CONTAINER_COUNT" ]; then
                if echo "$docker_ps_cache" | grep -q "^${cname}$"; then
                    status_text="Running"
                    status_color="${GREEN}"
                    local logs=$(docker logs --tail 50 "$cname" 2>&1 | grep "STATS" | tail -1)
                    if [ -n "$logs" ]; then
                        IFS='|' read -r conn cing mc_up mc_down <<< $(echo "$logs" | awk '{
                            cing=0; conn=0; up=""; down=""
                            for(j=1;j<=NF;j++){
                                if($j=="Connecting:") cing=$(j+1)+0
                                else if($j=="Connected:") conn=$(j+1)+0
                                else if($j=="Up:"){for(k=j+1;k<=NF;k++){if($k=="|"||$k~/Down:/)break; up=up (up?" ":"") $k}}
                                else if($j=="Down:"){for(k=j+1;k<=NF;k++){if($k=="|"||$k~/Uptime:/)break; down=down (down?" ":"") $k}}
                            }
                            printf "%d|%d|%s|%s", conn, cing, up, down
                        }')
                        c_clients="${conn:-0}/${cing:-0}"
                        c_up="${mc_up:-"-"}"
                        c_down="${mc_down:-"-"}"
                        [ -z "$c_up" ] && c_up="-"
                        [ -z "$c_down" ] && c_down="-"
                    fi
                    local dstats_line=$(echo "$all_dstats" | grep "^${cname} " 2>/dev/null)
                    if [ -n "$dstats_line" ]; then
                        c_cpu=$(echo "$dstats_line" | awk '{print $2}')
                        c_ram=$(echo "$dstats_line" | awk '{print $3}')
                    fi
                else
                    status_text="Stopped"
                    status_color="${RED}"
                fi
            else
                status_text="--"
                status_color="${YELLOW}"
            fi
            printf "  %-2s %-11s %b%-8s%b %-7s %-8s %-8s %-6s %-7s${EL}\n" \
                "$ci" "$cname" "$status_color" "$status_text" "${NC}" "$c_clients" "$c_up" "$c_down" "$c_cpu" "$c_ram"
        done

        echo -e "${EL}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}${EL}"
        local max_add=$((5 - CONTAINER_COUNT))
        [ "$max_add" -gt 0 ] && echo -e "  ${GREEN}[a]${NC} Add container(s)      (max: ${max_add} more)${EL}"
        [ "$CONTAINER_COUNT" -gt 1 ] && echo -e "  ${RED}[r]${NC} Remove container(s)   (min: 1 required)${EL}"
        echo -e "  ${GREEN}[s]${NC} Start a container${EL}"
        echo -e "  ${RED}[t]${NC} Stop a container${EL}"
        echo -e "  ${YELLOW}[x]${NC} Restart a container${EL}"
        echo -e "  ${CYAN}[q]${NC} QR code for container${EL}"
        echo -e "  [b] Back to menu${EL}"
        echo -e "${EL}"
        printf "\033[J"

        echo -e "  ${CYAN}────────────────────────────────────────${NC}"
        echo -ne "\033[?25h"
        read -t 5 -p "  Enter choice: " mc_choice < /dev/tty 2>/dev/null || { mc_choice=""; }
        echo -ne "\033[?25l"

        # Empty = just refresh
        [ -z "$mc_choice" ] && continue

        case "$mc_choice" in
            a)
                if [ "$CONTAINER_COUNT" -ge 5 ]; then
                    echo -e "  ${RED}Already at maximum (5).${NC}"
                    read -n 1 -s -r -p "  Press any key..." < /dev/tty || true
                    continue
                fi
                local max_add=$((5 - CONTAINER_COUNT))
                read -p "  How many to add? (1-${max_add}): " add_count < /dev/tty || true
                if ! [[ "$add_count" =~ ^[0-9]+$ ]] || [ "$add_count" -lt 1 ] || [ "$add_count" -gt "$max_add" ]; then
                    echo -e "  ${RED}Invalid.${NC}"
                    read -n 1 -s -r -p "  Press any key..." < /dev/tty || true
                    continue
                fi
                local old_count=$CONTAINER_COUNT
                CONTAINER_COUNT=$((CONTAINER_COUNT + add_count))
                save_settings
                for i in $(seq $((old_count + 1)) $CONTAINER_COUNT); do
                    local name=$(get_container_name $i)
                    local vol=$(get_volume_name $i)
                    docker volume create "$vol" 2>/dev/null || true
                    fix_volume_permissions $i
                    run_conduit_container $i
                    if [ $? -eq 0 ]; then
                        echo -e "  ${GREEN}✓ ${name} started${NC}"
                    else
                        echo -e "  ${RED}✗ Failed to start ${name}${NC}"
                    fi
                done
                read -n 1 -s -r -p "  Press any key..." < /dev/tty || true
                ;;
            r)
                if [ "$CONTAINER_COUNT" -le 1 ]; then
                    echo -e "  ${RED}Must keep at least 1 container.${NC}"
                    read -n 1 -s -r -p "  Press any key..." < /dev/tty || true
                    continue
                fi
                local max_rm=$((CONTAINER_COUNT - 1))
                read -p "  How many to remove? (1-${max_rm}): " rm_count < /dev/tty || true
                if ! [[ "$rm_count" =~ ^[0-9]+$ ]] || [ "$rm_count" -lt 1 ] || [ "$rm_count" -gt "$max_rm" ]; then
                    echo -e "  ${RED}Invalid.${NC}"
                    read -n 1 -s -r -p "  Press any key..." < /dev/tty || true
                    continue
                fi
                local old_count=$CONTAINER_COUNT
                CONTAINER_COUNT=$((CONTAINER_COUNT - rm_count))
                save_settings
                for i in $(seq $((CONTAINER_COUNT + 1)) $old_count); do
                    local name=$(get_container_name $i)
                    docker stop "$name" 2>/dev/null || true
                    docker rm "$name" 2>/dev/null || true
                    echo -e "  ${YELLOW}✓ ${name} removed${NC}"
                done
                read -n 1 -s -r -p "  Press any key..." < /dev/tty || true
                ;;
            s)
                read -p "  Start which container? (1-${CONTAINER_COUNT}, or 'all'): " sc_idx < /dev/tty || true
                if [ "$sc_idx" = "all" ]; then
                    for i in $(seq 1 $CONTAINER_COUNT); do
                        local name=$(get_container_name $i)
                        local vol=$(get_volume_name $i)
                        docker volume create "$vol" 2>/dev/null || true
                        fix_volume_permissions $i
                        run_conduit_container $i
                        if [ $? -eq 0 ]; then
                            echo -e "  ${GREEN}✓ ${name} started${NC}"
                        else
                            echo -e "  ${RED}✗ Failed to start ${name}${NC}"
                        fi
                    done
                elif [[ "$sc_idx" =~ ^[1-5]$ ]] && [ "$sc_idx" -le "$CONTAINER_COUNT" ]; then
                    local name=$(get_container_name $sc_idx)
                    local vol=$(get_volume_name $sc_idx)
                    docker volume create "$vol" 2>/dev/null || true
                    fix_volume_permissions $sc_idx
                    run_conduit_container $sc_idx
                    if [ $? -eq 0 ]; then
                        echo -e "  ${GREEN}✓ ${name} started${NC}"
                    else
                        echo -e "  ${RED}✗ Failed to start ${name}${NC}"
                    fi
                else
                    echo -e "  ${RED}Invalid.${NC}"
                fi
                read -n 1 -s -r -p "  Press any key..." < /dev/tty || true
                ;;
            t)
                read -p "  Stop which container? (1-${CONTAINER_COUNT}, or 'all'): " sc_idx < /dev/tty || true
                if [ "$sc_idx" = "all" ]; then
                    for i in $(seq 1 $CONTAINER_COUNT); do
                        local name=$(get_container_name $i)
                        docker stop "$name" 2>/dev/null || true
                        echo -e "  ${YELLOW}✓ ${name} stopped${NC}"
                    done
                elif [[ "$sc_idx" =~ ^[1-5]$ ]] && [ "$sc_idx" -le "$CONTAINER_COUNT" ]; then
                    local name=$(get_container_name $sc_idx)
                    docker stop "$name" 2>/dev/null || true
                    echo -e "  ${YELLOW}✓ ${name} stopped${NC}"
                else
                    echo -e "  ${RED}Invalid.${NC}"
                fi
                read -n 1 -s -r -p "  Press any key..." < /dev/tty || true
                ;;
            x)
                read -p "  Restart which container? (1-${CONTAINER_COUNT}, or 'all'): " sc_idx < /dev/tty || true
                if [ "$sc_idx" = "all" ]; then
                    local persist_dir="$INSTALL_DIR/traffic_stats"
                    if [ -s "$persist_dir/cumulative_data" ] || [ -s "$persist_dir/cumulative_ips" ]; then
                        echo -e "  ${CYAN}⟳ Saving tracker data snapshot...${NC}"
                        [ -s "$persist_dir/cumulative_data" ] && cp "$persist_dir/cumulative_data" "$persist_dir/cumulative_data.bak"
                        [ -s "$persist_dir/cumulative_ips" ] && cp "$persist_dir/cumulative_ips" "$persist_dir/cumulative_ips.bak"
                        [ -s "$persist_dir/geoip_cache" ] && cp "$persist_dir/geoip_cache" "$persist_dir/geoip_cache.bak"
                        echo -e "  ${GREEN}✓ Tracker data snapshot saved${NC}"
                    fi
                    for i in $(seq 1 $CONTAINER_COUNT); do
                        local name=$(get_container_name $i)
                        docker restart "$name" 2>/dev/null || true
                        echo -e "  ${GREEN}✓ ${name} restarted${NC}"
                    done
                    # Restart tracker to pick up new container state
                    if command -v systemctl &>/dev/null && systemctl is-active --quiet conduit-tracker.service 2>/dev/null; then
                        systemctl restart conduit-tracker.service 2>/dev/null || true
                    fi
                elif [[ "$sc_idx" =~ ^[1-5]$ ]] && [ "$sc_idx" -le "$CONTAINER_COUNT" ]; then
                    local name=$(get_container_name $sc_idx)
                    docker restart "$name" 2>/dev/null || true
                    echo -e "  ${GREEN}✓ ${name} restarted${NC}"
                else
                    echo -e "  ${RED}Invalid.${NC}"
                fi
                read -n 1 -s -r -p "  Press any key..." < /dev/tty || true
                ;;
            q)
                show_qr_code
                ;;
            b|"")
                stop_manage=1
                ;;
            *)
                echo -e "  ${RED}Invalid option.${NC}"
                read -n 1 -s -r -p "  Press any key..." < /dev/tty || true
                ;;
        esac
    done
    echo -ne "\033[?25h"
    tput rmcup 2>/dev/null || true
    trap - SIGINT SIGTERM
}

# Get default network interface
