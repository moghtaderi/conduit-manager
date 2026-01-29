update_conduit() {
    echo -e "${CYAN}═══ UPDATE CONDUIT ═══${NC}"
    echo ""

    echo "Current image: ${CONDUIT_IMAGE}"
    echo ""

    # Check for updates by pulling and capture output
    echo "Checking for updates..."
    local pull_output
    pull_output=$(docker pull "$CONDUIT_IMAGE" 2>&1)
    local pull_status=$?
    echo "$pull_output"

    if [ $pull_status -ne 0 ]; then
        echo -e "${RED}Failed to check for updates. Check your internet connection.${NC}"
        return 1
    fi

    # Verify image integrity
    if ! verify_image_digest "$CONDUIT_IMAGE_DIGEST" "$CONDUIT_IMAGE"; then
        return 1
    fi

    # Check if image was actually updated
    if echo "$pull_output" | grep -q "Status: Image is up to date"; then
        echo ""
        echo -e "${GREEN}Already running the latest version. No update needed.${NC}"
        return 0
    fi

    echo ""
    echo "Recreating container(s) with updated image..."

    # Remove and recreate all containers
    for i in $(seq 1 $CONTAINER_COUNT); do
        local name=$(get_container_name $i)
        docker rm -f "$name" 2>/dev/null || true
    done

    fix_volume_permissions
    for i in $(seq 1 $CONTAINER_COUNT); do
        run_conduit_container $i
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ $(get_container_name $i) updated and restarted${NC}"
        else
            echo -e "${RED}✗ Failed to start $(get_container_name $i)${NC}"
        fi
    done
}
