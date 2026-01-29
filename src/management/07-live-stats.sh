show_live_stats() {
    # Check if any container is running (single docker ps call)
    local ps_cache=$(docker ps --format '{{.Names}}' 2>/dev/null)
    local any_running=false
    for i in $(seq 1 $CONTAINER_COUNT); do
        local cname=$(get_container_name $i)
        if echo "$ps_cache" | grep -q "^${cname}$"; then
            any_running=true
            break
        fi
    done
    if [ "$any_running" = false ]; then
        print_header
        echo -e "${RED}Conduit is not running!${NC}"
        echo "Start it first with option 6 or 'conduit start'"
        read -n 1 -s -r -p "Press any key to continue..." < /dev/tty 2>/dev/null || true
        return 1
    fi

    if [ "$CONTAINER_COUNT" -le 1 ]; then
        # Single container - stream directly
        echo -e "${CYAN}Streaming live statistics... Press Ctrl+C to return to menu${NC}"
        echo -e "${YELLOW}(showing live logs filtered for [STATS])${NC}"
        echo ""
        trap 'echo -e "\n${CYAN}Returning to menu...${NC}"; return' SIGINT
        if grep --help 2>&1 | grep -q -- --line-buffered; then
            docker logs -f --tail 20 conduit 2>&1 | grep --line-buffered "\[STATS\]"
        else
            docker logs -f --tail 20 conduit 2>&1 | grep "\[STATS\]"
        fi
        trap - SIGINT
    else
        # Multi container - show container picker
        echo ""
        echo -e "${CYAN}Select container to view live stats:${NC}"
        echo ""
        for i in $(seq 1 $CONTAINER_COUNT); do
            local cname=$(get_container_name $i)
            local status="${RED}Stopped${NC}"
            echo "$ps_cache" | grep -q "^${cname}$" && status="${GREEN}Running${NC}"
            echo -e "  ${i}. ${cname}  [${status}]"
        done
        echo ""
        read -p "  Select (1-${CONTAINER_COUNT}): " idx < /dev/tty || true
        if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "$CONTAINER_COUNT" ]; then
            echo -e "${RED}Invalid selection.${NC}"
            return 1
        fi
        local target=$(get_container_name $idx)
        echo ""
        echo -e "${CYAN}Streaming live statistics from ${target}... Press Ctrl+C to return${NC}"
        echo ""
        trap 'echo -e "\n${CYAN}Returning to menu...${NC}"; return' SIGINT
        if grep --help 2>&1 | grep -q -- --line-buffered; then
            docker logs -f --tail 20 "$target" 2>&1 | grep --line-buffered "\[STATS\]"
        else
            docker logs -f --tail 20 "$target" 2>&1 | grep "\[STATS\]"
        fi
        trap - SIGINT
    fi
}

# format_bytes() - Convert bytes to human-readable format (B, KB, MB, GB)
