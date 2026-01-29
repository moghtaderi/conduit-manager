show_logs() {
    if ! docker ps -a 2>/dev/null | grep -q conduit; then
        echo -e "${RED}Conduit container not found.${NC}"
        return 1
    fi

    local target="conduit"
    if [ "$CONTAINER_COUNT" -gt 1 ]; then
        echo ""
        echo -e "${CYAN}Select container to view logs:${NC}"
        echo ""
        for i in $(seq 1 $CONTAINER_COUNT); do
            local cname=$(get_container_name $i)
            local status="${RED}Stopped${NC}"
            docker ps 2>/dev/null | grep -q "[[:space:]]${cname}$" && status="${GREEN}Running${NC}"
            echo -e "  ${i}. ${cname}  [${status}]"
        done
        echo ""
        read -p "  Select (1-${CONTAINER_COUNT}): " idx < /dev/tty || true
        if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "$CONTAINER_COUNT" ]; then
            echo -e "${RED}Invalid selection.${NC}"
            return 1
        fi
        target=$(get_container_name $idx)
    fi

    echo -e "${CYAN}Streaming logs from ${target} (filtered, no [STATS])... Press Ctrl+C to stop${NC}"
    echo ""

    docker logs -f "$target" 2>&1 | grep -v "\[STATS\]"
}

