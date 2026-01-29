check_and_offer_backup_restore() {
    if [ ! -d "$BACKUP_DIR" ]; then
        return 0
    fi

    local latest_backup=$(ls -t "$BACKUP_DIR"/conduit_key_*.json 2>/dev/null | head -1)

    if [ -z "$latest_backup" ]; then
        return 0
    fi

    local backup_filename=$(basename "$latest_backup")
    local backup_date=$(echo "$backup_filename" | sed -E 's/conduit_key_([0-9]{8})_([0-9]{6})\.json/\1/')
    local backup_time=$(echo "$backup_filename" | sed -E 's/conduit_key_([0-9]{8})_([0-9]{6})\.json/\2/')
    local formatted_date="${backup_date:0:4}-${backup_date:4:2}-${backup_date:6:2}"
    local formatted_time="${backup_time:0:2}:${backup_time:2:2}:${backup_time:4:2}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  📁 PREVIOUS NODE IDENTITY BACKUP FOUND${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  A backup of your node identity key was found:"
    echo -e "    ${YELLOW}File:${NC} $backup_filename"
    echo -e "    ${YELLOW}Date:${NC} $formatted_date $formatted_time"
    echo ""
    echo -e "  Restoring this key will:"
    echo -e "    • Preserve your node's identity on the Psiphon network"
    echo -e "    • Maintain any accumulated reputation"
    echo -e "    • Allow peers to reconnect to your known node ID"
    echo ""
    echo -e "  ${YELLOW}Note:${NC} If you don't restore, a new identity will be generated."
    echo ""

    while true; do
        read -p "  Do you want to restore your previous node identity? (y/n): " restore_choice < /dev/tty || true

        if [[ "$restore_choice" =~ ^[Yy]$ ]]; then
            echo ""
            log_info "Restoring node identity from backup..."

            docker volume create conduit-data 2>/dev/null || true

            # Try bind-mount, fall back to docker cp (Snap Docker compatibility)
            local restore_ok=false
            if docker run --rm -v conduit-data:/home/conduit/data -v "$BACKUP_DIR":/backup alpine \
                sh -c "cp /backup/$backup_filename /home/conduit/data/conduit_key.json && chown -R 1000:1000 /home/conduit/data" 2>/dev/null; then
                restore_ok=true
            else
                log_info "Bind-mount failed (Snap Docker?), trying docker cp..."
                local tmp_ctr="conduit-restore-tmp"
                docker create --name "$tmp_ctr" -v conduit-data:/home/conduit/data alpine true 2>/dev/null || true
                if docker cp "$latest_backup" "$tmp_ctr:/home/conduit/data/conduit_key.json" 2>/dev/null; then
                    docker run --rm -v conduit-data:/home/conduit/data alpine \
                        chown -R 1000:1000 /home/conduit/data 2>/dev/null || true
                    restore_ok=true
                fi
                docker rm -f "$tmp_ctr" 2>/dev/null || true
            fi

            if [ "$restore_ok" = "true" ]; then
                log_success "Node identity restored successfully!"
                echo ""
                return 0
            else
                log_error "Failed to restore backup. Proceeding with fresh install."
                echo ""
                return 1
            fi
        elif [[ "$restore_choice" =~ ^[Nn]$ ]]; then
            echo ""
            log_info "Skipping restore. A new node identity will be generated."
            echo ""
            return 1
        else
            echo "  Please enter y or n."
        fi
    done
}

