# Ensure we're running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This command must be run as root (use sudo conduit)${NC}"
    exit 1
fi

# Check if Docker is available
check_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}Error: Docker is not installed!${NC}"
        echo ""
        echo "Docker is required to run Conduit. Please reinstall:"
        echo "  curl -fsSL https://get.docker.com | sudo sh"
        echo ""
        echo "Or re-run the Conduit installer:"
        echo "  sudo bash conduit.sh"
        exit 1
    fi
    
    if ! docker info &>/dev/null; then
        echo -e "${RED}Error: Docker daemon is not running!${NC}"
        echo ""
        echo "Start Docker with:"
        echo "  sudo systemctl start docker       # For systemd"
        echo "  sudo /etc/init.d/docker start     # For SysVinit"
        echo "  sudo rc-service docker start      # For OpenRC"
        exit 1
    fi
}

# Run Docker check
check_docker

# Check for awk (needed for stats parsing)
if ! command -v awk &>/dev/null; then
    echo -e "${YELLOW}Warning: awk not found. Some stats may not display correctly.${NC}"
fi

# Helper: Get container name by index (1-based)
get_container_name() {
    local idx=${1:-1}
    if [ "$idx" -eq 1 ]; then
        echo "conduit"
    else
        echo "conduit-${idx}"
    fi
}

# Helper: Get volume name by index (1-based)
get_volume_name() {
    local idx=${1:-1}
    if [ "$idx" -eq 1 ]; then
        echo "conduit-data"
    else
        echo "conduit-data-${idx}"
    fi
}

# Helper: Fix volume permissions for conduit user (uid 1000)
fix_volume_permissions() {
    local idx=${1:-0}
    if [ "$idx" -eq 0 ]; then
        # Fix all volumes
        for i in $(seq 1 $CONTAINER_COUNT); do
            local vol=$(get_volume_name $i)
            docker run --rm -v "${vol}:/home/conduit/data" alpine \
                sh -c "chown -R 1000:1000 /home/conduit/data" 2>/dev/null || true
        done
    else
        local vol=$(get_volume_name $idx)
        docker run --rm -v "${vol}:/home/conduit/data" alpine \
            sh -c "chown -R 1000:1000 /home/conduit/data" 2>/dev/null || true
    fi
}

# Helper: Start/recreate conduit container with current settings
get_container_max_clients() {
    local idx=${1:-1}
    local var="MAX_CLIENTS_${idx}"
    local val="${!var}"
    echo "${val:-$MAX_CLIENTS}"
}

get_container_bandwidth() {
    local idx=${1:-1}
    local var="BANDWIDTH_${idx}"
    local val="${!var}"
    echo "${val:-$BANDWIDTH}"
}

