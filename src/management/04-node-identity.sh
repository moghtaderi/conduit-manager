get_node_id() {
    local vol="${1:-conduit-data}"
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        local mountpoint=$(docker volume inspect "$vol" --format '{{ .Mountpoint }}' 2>/dev/null)
        local key_json=""
        if [ -n "$mountpoint" ] && [ -f "$mountpoint/conduit_key.json" ]; then
            key_json=$(cat "$mountpoint/conduit_key.json" 2>/dev/null)
        else
            local tmp_ctr="conduit-nodeid-tmp"
            docker rm -f "$tmp_ctr" 2>/dev/null || true
            docker create --name "$tmp_ctr" -v "$vol":/data alpine true 2>/dev/null || true
            key_json=$(docker cp "$tmp_ctr:/data/conduit_key.json" - 2>/dev/null | tar -xO 2>/dev/null)
            docker rm -f "$tmp_ctr" 2>/dev/null || true
        fi
        if [ -n "$key_json" ]; then
            echo "$key_json" | grep "privateKeyBase64" | awk -F'"' '{print $4}' | base64 -d 2>/dev/null | tail -c 32 | base64 | tr -d '=\n'
        fi
    fi
}

get_raw_key() {
    local vol="${1:-conduit-data}"
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        local mountpoint=$(docker volume inspect "$vol" --format '{{ .Mountpoint }}' 2>/dev/null)
        local key_json=""
        if [ -n "$mountpoint" ] && [ -f "$mountpoint/conduit_key.json" ]; then
            key_json=$(cat "$mountpoint/conduit_key.json" 2>/dev/null)
        else
            local tmp_ctr="conduit-rawkey-tmp"
            docker rm -f "$tmp_ctr" 2>/dev/null || true
            docker create --name "$tmp_ctr" -v "$vol":/data alpine true 2>/dev/null || true
            key_json=$(docker cp "$tmp_ctr:/data/conduit_key.json" - 2>/dev/null | tar -xO 2>/dev/null)
            docker rm -f "$tmp_ctr" 2>/dev/null || true
        fi
        if [ -n "$key_json" ]; then
            echo "$key_json" | grep "privateKeyBase64" | awk -F'"' '{print $4}'
        fi
    fi
}

show_qr_code() {
    local idx="${1:-}"
    # If multiple containers and no index specified, prompt
    if [ -z "$idx" ] && [ "$CONTAINER_COUNT" -gt 1 ]; then
        echo ""
        echo -e "${CYAN}═══ SELECT CONTAINER ═══${NC}"
        for ci in $(seq 1 $CONTAINER_COUNT); do
            local cname=$(get_container_name $ci)
            echo -e "  ${ci}. ${cname}"
        done
        echo ""
        read -p "  Which container? (1-${CONTAINER_COUNT}): " idx < /dev/tty || true
        if ! [[ "$idx" =~ ^[1-5]$ ]] || [ "$idx" -gt "$CONTAINER_COUNT" ]; then
            echo -e "${RED}  Invalid selection.${NC}"
            return
        fi
    fi
    [ -z "$idx" ] && idx=1
    local vol=$(get_volume_name $idx)
    local cname=$(get_container_name $idx)

    clear
    local node_id=$(get_node_id "$vol")
    local raw_key=$(get_raw_key "$vol")
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    CONDUIT ID & QR CODE                           ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    if [ "$CONTAINER_COUNT" -gt 1 ]; then
        printf "${CYAN}║${NC}  Container:  ${BOLD}%-52s${CYAN}║${NC}\n" "$cname"
    fi
    if [ -n "$node_id" ]; then
        printf "${CYAN}║${NC}  Conduit ID: ${GREEN}%-52s${CYAN}║${NC}\n" "$node_id"
    else
        printf "${CYAN}║${NC}  Conduit ID: ${YELLOW}%-52s${CYAN}║${NC}\n" "Not available (start container first)"
    fi
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    if [ -n "$raw_key" ] && command -v qrencode &>/dev/null; then
        local hostname_str=$(hostname 2>/dev/null || echo "conduit")
        local claim_json="{\"version\":1,\"data\":{\"key\":\"${raw_key}\",\"name\":\"${hostname_str}\"}}"
        local claim_b64=$(echo -n "$claim_json" | base64 | tr -d '\n')
        local claim_url="network.ryve.app://(app)/conduits?claim=${claim_b64}"
        echo -e "${BOLD}  Scan to claim rewards:${NC}"
        echo ""
        qrencode -t ANSIUTF8 "$claim_url" 2>/dev/null
    elif ! command -v qrencode &>/dev/null; then
        echo -e "${YELLOW}  qrencode not installed. Install with: sudo apt install qrencode${NC}"
        echo -e "  ${CYAN}Claim rewards at: https://network.ryve.app${NC}"
    else
        echo -e "${YELLOW}  Key not available. Start container first.${NC}"
    fi
    echo ""
    read -n 1 -s -r -p "  Press any key to return..." < /dev/tty || true
}

