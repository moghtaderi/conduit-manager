run_conduit_container() {
    local idx=${1:-1}
    local name=$(get_container_name $idx)
    local vol=$(get_volume_name $idx)
    local mc=$(get_container_max_clients $idx)
    local bw=$(get_container_bandwidth $idx)
    docker run -d \
        --name "$name" \
        --restart unless-stopped \
        --log-opt max-size=15m \
        --log-opt max-file=3 \
        -v "${vol}:/home/conduit/data" \
        --network host \
        "$CONDUIT_IMAGE" \
        start --max-clients "$mc" --bandwidth "$bw" --stats-file
}

# Verify Docker image digest matches expected value (security check)
verify_image_digest() {
    local expected="$1"
    local image="$2"

    echo "Verifying image integrity..."

    local actual=$(docker inspect --format='{{index .RepoDigests 0}}' "$image" 2>/dev/null | grep -o 'sha256:[a-f0-9]*')

    if [ -z "$actual" ]; then
        echo -e "${YELLOW}[!] Could not verify image digest${NC}"
        return 0
    fi

    if [ "$actual" != "$expected" ]; then
        echo -e "${RED}[✗] Image digest mismatch!${NC}"
        echo -e "${RED}    Expected: $expected${NC}"
        echo -e "${RED}    Got:      $actual${NC}"
        echo -e "${RED}    This could indicate a compromised image. Aborting.${NC}"
        return 1
    fi

    echo -e "${GREEN}[✓] Image digest verified: ${actual:0:20}...${NC}"
    return 0
}

