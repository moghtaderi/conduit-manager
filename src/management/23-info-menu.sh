show_info_menu() {
    local redraw=true
    while true; do
        if [ "$redraw" = true ]; then
            clear
            echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}  INFO & HELP${NC}"
            echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
            echo ""
            echo -e "  1. 📡 How the Tracker Works"
            echo -e "  2. 📊 Understanding the Stats Pages"
            echo -e "  3. 📦 Containers & Scaling"
            echo -e "  4. 🔒 Privacy & Security"
            echo -e "  5. 🚀 About Psiphon Conduit"
            echo ""
            echo -e "  [b] Back to menu"
            echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
            echo ""
            redraw=true
        fi
        read -p "  Select page: " info_choice < /dev/tty || break
        case "$info_choice" in
            1) _info_tracker; redraw=true ;;
            2) _info_stats; redraw=true ;;
            3) _info_containers; redraw=true ;;
            4) _info_privacy; redraw=true ;;
            5) show_about; redraw=true ;;
            b|"") break ;;
            *) echo -e "  ${RED}Invalid.${NC}"; sleep 1; redraw=true ;;
        esac
    done
}

_info_tracker() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  HOW THE TRACKER WORKS${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}What is it?${NC}"
    echo -e "  A background systemd service (conduit-tracker.service) that"
    echo -e "  monitors network traffic on your server using tcpdump."
    echo -e "  It runs continuously and captures ALL TCP/UDP traffic"
    echo -e "  (excluding SSH port 22) to track where traffic goes."
    echo ""
    echo -e "  ${BOLD}How it works${NC}"
    echo -e "  Every 15 seconds the tracker:"
    echo -e "    ${YELLOW}1.${NC} Captures network packets via tcpdump"
    echo -e "    ${YELLOW}2.${NC} Extracts source/destination IPs and byte counts"
    echo -e "    ${YELLOW}3.${NC} Resolves each IP to a country using GeoIP"
    echo -e "    ${YELLOW}4.${NC} Saves cumulative data to disk"
    echo ""
    echo -e "  ${BOLD}Data files${NC}  ${DIM}(in /opt/conduit/traffic_stats/)${NC}"
    echo -e "    ${CYAN}cumulative_data${NC}  - Country traffic totals (bytes in/out)"
    echo -e "    ${CYAN}cumulative_ips${NC}   - All unique IPs ever seen + country"
    echo -e "    ${CYAN}tracker_snapshot${NC} - Last 15-second cycle (for live views)"
    echo ""
    echo -e "  ${BOLD}Important${NC}"
    echo -e "  The tracker captures ALL server traffic, not just Conduit."
    echo -e "  IP counts include system updates, DNS, Docker pulls, etc."
    echo -e "  This is why unique IP counts are higher than client counts."
    echo -e "  To reset all data: Settings > Reset tracker data."
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    read -n 1 -s -r -p "  Press any key to return..." < /dev/tty || true
}

_info_stats() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  UNDERSTANDING THE STATS PAGES${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Unique IPs vs Clients${NC}"
    echo -e "    ${YELLOW}IPs${NC}     = Total unique IP addresses seen in ALL network"
    echo -e "            traffic. Includes non-Conduit traffic (system"
    echo -e "            updates, DNS, Docker, etc). Always higher."
    echo -e "    ${GREEN}Clients${NC} = Actual Psiphon peers connected to your Conduit"
    echo -e "            containers. Comes from Docker logs. This is"
    echo -e "            the real number of people you are helping."
    echo ""
    echo -e "  ${BOLD}Dashboard (option 1)${NC}"
    echo -e "    Shows status, resources, traffic totals, and two"
    echo -e "    side-by-side TOP 5 charts:"
    echo -e "      ${GREEN}Active Clients${NC} - Estimated clients per country"
    echo -e "      ${YELLOW}Top Upload${NC}     - Countries you upload most to"
    echo ""
    echo -e "  ${BOLD}Live Peers (option 4)${NC}"
    echo -e "    Full-page traffic breakdown by country. Shows:"
    echo -e "      Total bytes, Speed (KB/s), IPs / Clients per country"
    echo -e "    Client counts are estimated from the snapshot"
    echo -e "    distribution scaled to actual connected count."
    echo ""
    echo -e "  ${BOLD}Advanced Stats (a)${NC}"
    echo -e "    Container resources (CPU, RAM, clients, bandwidth),"
    echo -e "    network speed, tracker status, and TOP 7 charts"
    echo -e "    for unique IPs, download, and upload by country."
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    read -n 1 -s -r -p "  Press any key to return..." < /dev/tty || true
}

_info_containers() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  CONTAINERS & SCALING${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}What are containers?${NC}"
    echo -e "  Each container is an independent Conduit node running"
    echo -e "  in Docker. Multiple containers let you serve more"
    echo -e "  clients simultaneously from the same server."
    echo ""
    echo -e "  ${BOLD}Naming${NC}"
    echo -e "    Container 1: ${CYAN}conduit${NC}      Volume: ${CYAN}conduit-data${NC}"
    echo -e "    Container 2: ${CYAN}conduit-2${NC}    Volume: ${CYAN}conduit-data-2${NC}"
    echo -e "    Container 3: ${CYAN}conduit-3${NC}    Volume: ${CYAN}conduit-data-3${NC}"
    echo -e "    ...up to 5 containers."
    echo ""
    echo -e "  ${BOLD}Scaling recommendations${NC}"
    echo -e "    ${YELLOW}1 CPU / <1GB RAM:${NC}  Stick with 1 container"
    echo -e "    ${YELLOW}2 CPUs / 2GB RAM:${NC}  1-2 containers"
    echo -e "    ${GREEN}4+ CPUs / 4GB RAM:${NC} 3-5 containers"
    echo -e "  Each container uses ~50MB RAM per 100 clients."
    echo ""
    echo -e "  ${BOLD}Per-container settings${NC}"
    echo -e "  You can set different max-clients and bandwidth for"
    echo -e "  each container in Settings > Change settings. Choose"
    echo -e "  'Apply to specific container' to customize individually."
    echo ""
    echo -e "  ${BOLD}Managing${NC}"
    echo -e "  Use Manage Containers (c) to add/remove containers,"
    echo -e "  start/stop individual ones, or view per-container stats."
    echo -e "  Each container has its own volume (identity key)."
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    read -n 1 -s -r -p "  Press any key to return..." < /dev/tty || true
}

_info_privacy() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  PRIVACY & SECURITY${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Is my traffic visible?${NC}"
    echo -e "  ${GREEN}No.${NC} All Conduit traffic is end-to-end encrypted using"
    echo -e "  WebRTC + DTLS. You cannot see what users are browsing."
    echo -e "  The connection looks like a regular video call."
    echo ""
    echo -e "  ${BOLD}What data is stored?${NC}"
    echo -e "  Conduit Manager stores:"
    echo -e "    ${GREEN}Node identity key${NC} - Your unique node ID (in Docker volume)"
    echo -e "    ${GREEN}Settings${NC}          - Max clients, bandwidth, container count"
    echo -e "    ${GREEN}Tracker stats${NC}     - Country-level traffic aggregates"
    echo -e "  ${RED}No${NC} user browsing data, IP logs, or personal info is stored."
    echo ""
    echo -e "  ${BOLD}What can the tracker see?${NC}"
    echo -e "  The tracker only records:"
    echo -e "    - Which countries connect (via GeoIP lookup)"
    echo -e "    - How many bytes flow in/out per country"
    echo -e "    - Total unique IP addresses (not logged individually)"
    echo -e "  It cannot see URLs, content, or decrypt any traffic."
    echo ""
    echo -e "  ${BOLD}Uninstall${NC}"
    echo -e "  Full uninstall (option 9 > Uninstall) removes:"
    echo -e "    - All containers and Docker volumes"
    echo -e "    - Tracker service and all stats data"
    echo -e "    - Settings, systemd service files"
    echo -e "    - The conduit command itself"
    echo -e "  Nothing is left behind on your system."
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    read -n 1 -s -r -p "  Press any key to return..." < /dev/tty || true
}

# Command line interface
