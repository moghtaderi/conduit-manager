print_header() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    printf "║                🚀 PSIPHON CONDUIT MANAGER v%-5s                  ║\n" "${VERSION}"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_live_stats_header() {
    local EL="\033[K"
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${EL}"
    printf "║  ${NC}🚀 PSIPHON CONDUIT MANAGER v%-5s   ${CYAN}CONDUIT LIVE STATISTICS      ║${EL}\n" "${VERSION}"
    echo -e "╠═══════════════════════════════════════════════════════════════════╣${EL}"
    # Check for per-container overrides
    local has_overrides=false
    for i in $(seq 1 $CONTAINER_COUNT); do
        local mc_var="MAX_CLIENTS_${i}"
        local bw_var="BANDWIDTH_${i}"
        if [ -n "${!mc_var}" ] || [ -n "${!bw_var}" ]; then
            has_overrides=true
            break
        fi
    done
    if [ "$has_overrides" = true ] && [ "$CONTAINER_COUNT" -gt 1 ]; then
        for i in $(seq 1 $CONTAINER_COUNT); do
            local mc=$(get_container_max_clients $i)
            local bw=$(get_container_bandwidth $i)
            local bw_d="Unlimited"
            [ "$bw" != "-1" ] && bw_d="${bw}Mbps"
            local line="$(get_container_name $i): ${mc} clients, ${bw_d}"
            printf "║  ${GREEN}%-64s${CYAN}║${EL}\n" "$line"
        done
    else
        printf "║  Max Clients: ${GREEN}%-52s${CYAN}║${EL}\n" "${MAX_CLIENTS}"
        if [ "$BANDWIDTH" == "-1" ]; then
            printf "║  Bandwidth:   ${GREEN}%-52s${CYAN}║${EL}\n" "Unlimited"
        else
            printf "║  Bandwidth:   ${GREEN}%-52s${CYAN}║${EL}\n" "${BANDWIDTH} Mbps"
        fi
    fi
    echo -e "╚═══════════════════════════════════════════════════════════════════╝${EL}"
    echo -e "${NC}\033[K"
}



