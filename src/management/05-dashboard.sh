show_dashboard() {
    local stop_dashboard=0
    # Setup trap to catch signals gracefully
    trap 'stop_dashboard=1' SIGINT SIGTERM
    
    # Use alternate screen buffer if available for smoother experience
    tput smcup 2>/dev/null || true
    echo -ne "\033[?25l" # Hide cursor
    # Initial clear
    clear

    while [ $stop_dashboard -eq 0 ]; do
        # Move cursor to top-left (0,0)
        # We NO LONGER clear the screen here to avoid the "full black" flash
        if ! tput cup 0 0 2>/dev/null; then
            printf "\033[H"
        fi
        
        print_live_stats_header
        
        show_status "live"
        
        # Check data cap
        if [ "$DATA_CAP_GB" -gt 0 ] 2>/dev/null; then
            local usage=$(get_data_usage)
            local used_rx=$(echo "$usage" | awk '{print $1}')
            local used_tx=$(echo "$usage" | awk '{print $2}')
            local total_used=$((used_rx + used_tx + ${DATA_CAP_PRIOR_USAGE:-0}))
            local cap_gb_fmt=$(format_gb $total_used)
            echo -e "${CYAN}═══ DATA USAGE ═══${NC}\033[K"
            echo -e "  Usage: ${YELLOW}${cap_gb_fmt} GB${NC} / ${GREEN}${DATA_CAP_GB} GB${NC}\033[K"
            if ! check_data_cap; then
                echo -e "  ${RED}⚠ DATA CAP EXCEEDED - Containers stopped!${NC}\033[K"
            fi
            echo -e "\033[K"
        fi

        # Side-by-side: Active Clients | Top Upload
        local snap_file="$INSTALL_DIR/traffic_stats/tracker_snapshot"
        local data_file="$INSTALL_DIR/traffic_stats/cumulative_data"
        if [ -s "$snap_file" ] || [ -s "$data_file" ]; then
            # Reuse connected count from show_status (already cached)
            local dash_clients=${_total_connected:-0}

            # Left column: Active Clients per country (estimated from snapshot distribution)
            local left_lines=()
            if [ -s "$snap_file" ] && [ "$dash_clients" -gt 0 ]; then
                local snap_data
                snap_data=$(awk -F'|' '{if($2!=""&&$4!="") seen[$2"|"$4]=1} END{for(k in seen){split(k,a,"|");c[a[1]]++} for(co in c) print c[co]"|"co}' "$snap_file" 2>/dev/null | sort -t'|' -k1 -nr | head -5)
                local snap_total=0
                if [ -n "$snap_data" ]; then
                    while IFS='|' read -r cnt co; do
                        snap_total=$((snap_total + cnt))
                    done <<< "$snap_data"
                fi
                [ "$snap_total" -eq 0 ] && snap_total=1
                if [ -n "$snap_data" ]; then
                    while IFS='|' read -r cnt country; do
                        [ -z "$country" ] && continue
                        country="${country%% - #*}"
                        local est=$(( (cnt * dash_clients) / snap_total ))
                        [ "$est" -eq 0 ] && [ "$cnt" -gt 0 ] && est=1
                        local pct=$((est * 100 / dash_clients))
                        [ "$pct" -gt 100 ] && pct=100
                        local bl=$((pct / 20)); [ "$bl" -lt 1 ] && bl=1; [ "$bl" -gt 5 ] && bl=5
                        local bf=""; local bp=""; for ((bi=0; bi<bl; bi++)); do bf+="█"; done; for ((bi=bl; bi<5; bi++)); do bp+=" "; done
                        left_lines+=("$(printf "%-11.11s %3d%% \033[32m%s%s\033[0m %5d" "$country" "$pct" "$bf" "$bp" "$est")")
                    done <<< "$snap_data"
                fi
            fi

            # Right column: Top 5 Upload (cumulative outbound bytes per country)
            local right_lines=()
            if [ -s "$data_file" ]; then
                local all_upload
                all_upload=$(awk -F'|' '{if($1!="" && $3+0>0) print $3"|"$1}' "$data_file" 2>/dev/null | sort -t'|' -k1 -nr)
                local top5_upload=$(echo "$all_upload" | head -5)
                local total_upload=0
                if [ -n "$all_upload" ]; then
                    while IFS='|' read -r bytes co; do
                        bytes=$(printf '%.0f' "${bytes:-0}" 2>/dev/null) || bytes=0
                        total_upload=$((total_upload + bytes))
                    done <<< "$all_upload"
                fi
                [ "$total_upload" -eq 0 ] && total_upload=1
                if [ -n "$top5_upload" ]; then
                    while IFS='|' read -r bytes country; do
                        [ -z "$country" ] && continue
                        country="${country%% - #*}"
                        bytes=$(printf '%.0f' "${bytes:-0}" 2>/dev/null) || bytes=0
                        local pct=$((bytes * 100 / total_upload))
                        local bl=$((pct / 20)); [ "$bl" -lt 1 ] && bl=1; [ "$bl" -gt 5 ] && bl=5
                        local bf=""; local bp=""; for ((bi=0; bi<bl; bi++)); do bf+="█"; done; for ((bi=bl; bi<5; bi++)); do bp+=" "; done
                        local fmt_bytes=$(format_bytes $bytes)
                        right_lines+=("$(printf "%-11.11s %3d%% \033[35m%s%s\033[0m %9s" "$country" "$pct" "$bf" "$bp" "$fmt_bytes")")
                    done <<< "$top5_upload"
                fi
            fi

            # Print side by side
            printf "  ${GREEN}${BOLD}%-30s${NC} ${YELLOW}${BOLD}%s${NC}\033[K\n" "ACTIVE CLIENTS" "TOP 5 UPLOAD"
            local max_rows=${#left_lines[@]}
            [ ${#right_lines[@]} -gt $max_rows ] && max_rows=${#right_lines[@]}
            for ((ri=0; ri<max_rows; ri++)); do
                local lc="${left_lines[$ri]:-}"
                local rc="${right_lines[$ri]:-}"
                if [ -n "$lc" ] && [ -n "$rc" ]; then
                    printf "  "
                    echo -ne "$lc"
                    printf "   "
                    echo -e "$rc\033[K"
                elif [ -n "$lc" ]; then
                    printf "  "
                    echo -e "$lc\033[K"
                elif [ -n "$rc" ]; then
                    printf "  %-30s " ""
                    echo -e "$rc\033[K"
                fi
            done
            echo -e "\033[K"
        fi

        echo -e "${BOLD}Refreshes every 5 seconds. Press any key to return to menu...${NC}\033[K"
        
        # Clear any leftover lines below the dashboard content (Erase to End of Display)
        # This only cleans up if the dashboard gets shorter
        if ! tput ed 2>/dev/null; then
            printf "\033[J"
        fi
        
        # Wait 4 seconds for keypress (compensating for processing time)
        # Redirect from /dev/tty ensures it works when the script is piped
        if read -t 4 -n 1 -s < /dev/tty 2>/dev/null; then
            stop_dashboard=1
        fi
    done
    
    echo -ne "\033[?25h" # Show cursor
    # Restore main screen buffer
    tput rmcup 2>/dev/null || true
    trap - SIGINT SIGTERM # Reset traps
}

