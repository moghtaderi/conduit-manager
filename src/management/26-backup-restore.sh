backup_key() {
    echo -e "${CYAN}═══ BACKUP CONDUIT NODE KEY ═══${NC}"
    echo ""

    # Create backup directory
    mkdir -p "$INSTALL_DIR/backups"

    # Create timestamped backup
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$INSTALL_DIR/backups/conduit_key_${timestamp}.json"

    # Try direct mountpoint access first, fall back to docker cp (Snap Docker)
    local mountpoint=$(docker volume inspect conduit-data --format '{{ .Mountpoint }}' 2>/dev/null)

    if [ -n "$mountpoint" ] && [ -f "$mountpoint/conduit_key.json" ]; then
        if ! cp "$mountpoint/conduit_key.json" "$backup_file"; then
            echo -e "${RED}Error: Failed to copy key file${NC}"
            return 1
        fi
    else
        # Use docker cp fallback (works with Snap Docker)
        local tmp_ctr="conduit-backup-tmp"
        docker create --name "$tmp_ctr" -v conduit-data:/data alpine true 2>/dev/null || true
        if ! docker cp "$tmp_ctr:/data/conduit_key.json" "$backup_file" 2>/dev/null; then
            docker rm -f "$tmp_ctr" 2>/dev/null || true
            echo -e "${RED}Error: No node key found. Has Conduit been started at least once?${NC}"
            return 1
        fi
        docker rm -f "$tmp_ctr" 2>/dev/null || true
    fi

    chmod 600 "$backup_file"

    # Get node ID for display
    local node_id=$(cat "$backup_file" | grep "privateKeyBase64" | awk -F'"' '{print $4}' | base64 -d 2>/dev/null | tail -c 32 | base64 | tr -d '=\n')

    echo -e "${GREEN}✓ Backup created successfully${NC}"
    echo ""
    echo "  Backup file: ${CYAN}${backup_file}${NC}"
    echo "  Node ID:     ${CYAN}${node_id}${NC}"
    echo ""
    echo -e "${YELLOW}Important:${NC} Store this backup securely. It contains your node's"
    echo "private key which identifies your node on the Psiphon network."
    echo ""

    # List all backups
    echo "All backups:"
    ls -la "$INSTALL_DIR/backups/"*.json 2>/dev/null | awk '{print "  " $9 " (" $5 " bytes)"}'
}

restore_key() {
    echo -e "${CYAN}═══ RESTORE CONDUIT NODE KEY ═══${NC}"
    echo ""

    local backup_dir="$INSTALL_DIR/backups"

    # Check if backup directory exists and has files
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir"/*.json 2>/dev/null)" ]; then
        echo -e "${YELLOW}No backups found in ${backup_dir}${NC}"
        echo ""
        echo "To restore from a custom path, provide the file path:"
        read -p "  Backup file path (or press Enter to cancel): " custom_path < /dev/tty || true

        if [ -z "$custom_path" ]; then
            echo "Restore cancelled."
            return 0
        fi

        if [ ! -f "$custom_path" ]; then
            echo -e "${RED}Error: File not found: ${custom_path}${NC}"
            return 1
        fi

        local backup_file="$custom_path"
    else
        # List available backups
        echo "Available backups:"
        local i=1
        local backups=()
        for f in "$backup_dir"/*.json; do
            backups+=("$f")
            local node_id=$(cat "$f" | grep "privateKeyBase64" | awk -F'"' '{print $4}' | base64 -d 2>/dev/null | tail -c 32 | base64 | tr -d '=\n' 2>/dev/null)
            echo "  ${i}. $(basename "$f") - Node: ${node_id:-unknown}"
            i=$((i + 1))
        done
        echo ""

        read -p "  Select backup number (or 0 to cancel): " selection < /dev/tty || true

        if [ "$selection" = "0" ] || [ -z "$selection" ]; then
            echo "Restore cancelled."
            return 0
        fi

        if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#backups[@]} ]; then
            echo -e "${RED}Invalid selection${NC}"
            return 1
        fi

        backup_file="${backups[$((selection - 1))]}"
    fi

    echo ""
    echo -e "${YELLOW}Warning:${NC} This will replace the current node key."
    echo "The container will be stopped and restarted."
    echo ""
    read -p "Proceed with restore? [y/N] " confirm < /dev/tty || true

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Restore cancelled."
        return 0
    fi

    # Stop all containers
    echo ""
    echo "Stopping Conduit..."
    stop_conduit

    # Try direct mountpoint access, fall back to docker cp (Snap Docker)
    local mountpoint=$(docker volume inspect conduit-data --format '{{ .Mountpoint }}' 2>/dev/null)
    local use_docker_cp=false

    if [ -z "$mountpoint" ] || [ ! -d "$mountpoint" ]; then
        use_docker_cp=true
    fi

    # Backup current key if exists
    if [ "$use_docker_cp" = "true" ]; then
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        mkdir -p "$backup_dir"
        local tmp_ctr="conduit-restore-tmp"
        docker create --name "$tmp_ctr" -v conduit-data:/data alpine true 2>/dev/null || true
        if docker cp "$tmp_ctr:/data/conduit_key.json" "$backup_dir/conduit_key_pre_restore_${timestamp}.json" 2>/dev/null; then
            echo "  Current key backed up to: conduit_key_pre_restore_${timestamp}.json"
        fi
        # Copy new key in
        if ! docker cp "$backup_file" "$tmp_ctr:/data/conduit_key.json" 2>/dev/null; then
            docker rm -f "$tmp_ctr" 2>/dev/null || true
            echo -e "${RED}Error: Failed to copy key into container volume${NC}"
            return 1
        fi
        docker rm -f "$tmp_ctr" 2>/dev/null || true
        # Fix ownership
        docker run --rm -v conduit-data:/data alpine chown 1000:1000 /data/conduit_key.json 2>/dev/null || true
    else
        if [ -f "$mountpoint/conduit_key.json" ]; then
            local timestamp=$(date '+%Y%m%d_%H%M%S')
            mkdir -p "$backup_dir"
            cp "$mountpoint/conduit_key.json" "$backup_dir/conduit_key_pre_restore_${timestamp}.json"
            echo "  Current key backed up to: conduit_key_pre_restore_${timestamp}.json"
        fi
        if ! cp "$backup_file" "$mountpoint/conduit_key.json"; then
            echo -e "${RED}Error: Failed to copy key to volume${NC}"
            return 1
        fi
        chmod 600 "$mountpoint/conduit_key.json"
    fi

    # Restart all containers
    echo "Starting Conduit..."
    start_conduit

    local node_id=$(cat "$backup_file" | grep "privateKeyBase64" | awk -F'"' '{print $4}' | base64 -d 2>/dev/null | tail -c 32 | base64 | tr -d '=\n')

    echo ""
    echo -e "${GREEN}✓ Node key restored successfully${NC}"
    echo "  Node ID: ${CYAN}${node_id}${NC}"
}

