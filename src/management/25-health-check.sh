health_check() {
    echo -e "${CYAN}═══ CONDUIT HEALTH CHECK ═══${NC}"
    echo ""

    local all_ok=true

    # 1. Check if Docker is running
    echo -n "Docker daemon:        "
    if docker info &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC} - Docker is not running"
        all_ok=false
    fi

    # 2-5. Check each container
    for i in $(seq 1 $CONTAINER_COUNT); do
        local cname=$(get_container_name $i)
        local vname=$(get_volume_name $i)

        if [ "$CONTAINER_COUNT" -gt 1 ]; then
            echo ""
            echo -e "${CYAN}--- ${cname} ---${NC}"
        fi

        echo -n "Container exists:     "
        if docker ps -a 2>/dev/null | grep -q "[[:space:]]${cname}$"; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC} - Container not found"
            all_ok=false
        fi

        echo -n "Container running:    "
        if docker ps 2>/dev/null | grep -q "[[:space:]]${cname}$"; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC} - Container is stopped"
            all_ok=false
        fi

        echo -n "Restart count:        "
        local restarts=$(docker inspect --format='{{.RestartCount}}' "$cname" 2>/dev/null)
        if [ -n "$restarts" ]; then
            if [ "$restarts" -eq 0 ]; then
                echo -e "${GREEN}${restarts}${NC} (healthy)"
            elif [ "$restarts" -lt 5 ]; then
                echo -e "${YELLOW}${restarts}${NC} (some restarts)"
            else
                echo -e "${RED}${restarts}${NC} (excessive restarts)"
                all_ok=false
            fi
        else
            echo -e "${YELLOW}N/A${NC}"
        fi

        # Single docker logs call for network + stats checks
        local hc_logs=$(docker logs --tail 100 "$cname" 2>&1)
        local hc_stats_lines=$(echo "$hc_logs" | grep "\[STATS\]" || true)
        local hc_stats_count=0
        if [ -n "$hc_stats_lines" ]; then
            hc_stats_count=$(echo "$hc_stats_lines" | wc -l | tr -d ' ')
        fi
        hc_stats_count=${hc_stats_count:-0}
        local hc_last_stat=$(echo "$hc_stats_lines" | tail -1)
        local hc_connected=$(echo "$hc_last_stat" | sed -n 's/.*Connected:[[:space:]]*\([0-9]*\).*/\1/p' | head -1 | tr -d '\n')
        hc_connected=${hc_connected:-0}
        local hc_connecting=$(echo "$hc_last_stat" | sed -n 's/.*Connecting:[[:space:]]*\([0-9]*\).*/\1/p' | head -1 | tr -d '\n')
        hc_connecting=${hc_connecting:-0}

        echo -n "Network connection:   "
        if [ "$hc_connected" -gt 0 ] 2>/dev/null; then
            echo -e "${GREEN}OK${NC} (${hc_connected} peers connected, ${hc_connecting} connecting)"
        elif [ "$hc_stats_count" -gt 0 ] 2>/dev/null; then
            if [ "$hc_connecting" -gt 0 ] 2>/dev/null; then
                echo -e "${GREEN}OK${NC} (Connected, ${hc_connecting} peers connecting)"
            else
                echo -e "${GREEN}OK${NC} (Connected, awaiting peers)"
            fi
        else
            local info_lines=$(echo "$hc_logs" | grep -c "\[INFO\]" 2>/dev/null || echo 0)
            info_lines=${info_lines:-0}
            if [ "$info_lines" -gt 0 ] 2>/dev/null; then
                echo -e "${YELLOW}CONNECTING${NC} - Establishing connection..."
            else
                echo -e "${YELLOW}WAITING${NC} - Starting up..."
            fi
        fi

        echo -n "Stats output:         "
        if [ "$hc_stats_count" -gt 0 ] 2>/dev/null; then
            echo -e "${GREEN}OK${NC} (${hc_stats_count} entries)"
        else
            echo -e "${YELLOW}NONE${NC} - Run 'conduit restart' to enable"
        fi

        echo -n "Data volume:          "
        if docker volume inspect "$vname" &>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC} - Volume not found"
            all_ok=false
        fi

        echo -n "Network (host mode):  "
        local network_mode=$(docker inspect --format='{{.HostConfig.NetworkMode}}' "$cname" 2>/dev/null)
        if [ "$network_mode" = "host" ]; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}WARN${NC} - Not using host network mode"
        fi
    done

    # Node key check (only on first volume)
    if [ "$CONTAINER_COUNT" -gt 1 ]; then
        echo ""
        echo -e "${CYAN}--- Shared ---${NC}"
    fi
    echo -n "Node identity key:    "
    local mountpoint=$(docker volume inspect conduit-data --format '{{ .Mountpoint }}' 2>/dev/null)
    local key_found=false
    if [ -n "$mountpoint" ] && [ -f "$mountpoint/conduit_key.json" ]; then
        key_found=true
    else
        # Snap Docker fallback: check via docker cp
        local tmp_ctr="conduit-health-tmp"
        docker rm -f "$tmp_ctr" 2>/dev/null || true
        if docker create --name "$tmp_ctr" -v conduit-data:/data alpine true 2>/dev/null; then
            if docker cp "$tmp_ctr:/data/conduit_key.json" - >/dev/null 2>&1; then
                key_found=true
            fi
            docker rm -f "$tmp_ctr" 2>/dev/null || true
        fi
    fi
    if [ "$key_found" = true ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}PENDING${NC} - Will be created on first run"
    fi

    echo ""
    if [ "$all_ok" = true ]; then
        echo -e "${GREEN}✓ All health checks passed${NC}"
        return 0
    else
        echo -e "${RED}✗ Some health checks failed${NC}"
        return 1
    fi
}

