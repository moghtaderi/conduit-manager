show_usage() {
    echo "Psiphon Conduit Manager v${VERSION}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (no args)      Install or open management menu if already installed"
    echo "  --reinstall    Force fresh reinstall"
    echo "  --uninstall    Completely remove Conduit and all components"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo bash $0              # Install or open menu"
    echo "  sudo bash $0 --reinstall  # Fresh install"
    echo "  sudo bash $0 --uninstall  # Remove everything"
    echo ""
    echo "After install, use: conduit"
}

main() {
    # Handle command line arguments
    case "${1:-}" in
        --uninstall|-u)
            check_root
            uninstall
            exit 0
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        --reinstall)
            # Force reinstall
            FORCE_REINSTALL=true
            ;;
    esac
    
    print_header
    check_root
    detect_os
    
    # Ensure all tools (including new ones like tcpdump) are present
    check_dependencies
    
    # Check if already installed
    while [ -f "$INSTALL_DIR/conduit" ] && [ "$FORCE_REINSTALL" != "true" ]; do
        echo -e "${GREEN}Conduit is already installed!${NC}"
        echo ""
        echo "What would you like to do?"
        echo ""
        echo "  1. 📊 Open management menu"
        echo "  2. 🔄 Reinstall (fresh install)"
        echo "  3. 🗑️  Uninstall"
        echo "  0. 🚪 Exit"
        echo ""
        read -p "  Enter choice: " choice < /dev/tty || true

        case "$choice" in
            1)
                echo -e "${CYAN}Updating management script and opening menu...${NC}"
                create_management_script
                exec "$INSTALL_DIR/conduit" menu
                ;;
            2)
                echo ""
                log_info "Starting fresh reinstall..."
                break
                ;;
            3)
                uninstall
                exit 0
                ;;
            0)
                echo "Exiting."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice: ${NC}${YELLOW}$choice${NC}"
                echo -e "${CYAN}Returning to installer...${NC}"
                sleep 1
                ;;
        esac
    done

    # Interactive settings prompt (max-clients, bandwidth)
    prompt_settings

    echo ""
    echo -e "${CYAN}Starting installation...${NC}"
    echo ""

    #───────────────────────────────────────────────────────────────
    # Installation Steps (5 steps if backup exists, otherwise 4)
    #───────────────────────────────────────────────────────────────

    # Step 1: Install Docker (if not already installed)
    log_info "Step 1/5: Installing Docker..."
    install_docker

    echo ""

    # Step 2: Check for and optionally restore backup keys
    # This preserves node identity if user had a previous installation
    log_info "Step 2/5: Checking for previous node identity..."
    check_and_offer_backup_restore || true

    echo ""

    # Step 3: Start Conduit container
    log_info "Step 3/5: Starting Conduit..."
    # Clean up any existing containers from previous install/scaling
    docker stop conduit 2>/dev/null || true
    docker rm -f conduit 2>/dev/null || true
    for i in 2 3 4 5; do
        docker stop "conduit-${i}" 2>/dev/null || true
        docker rm -f "conduit-${i}" 2>/dev/null || true
    done
    run_conduit
    
    echo ""

    # Step 4: Save settings and configure auto-start service
    log_info "Step 4/5: Setting up auto-start..."
    save_settings_install
    setup_autostart

    echo ""

    # Step 5: Create the 'conduit' CLI management script
    log_info "Step 5/5: Creating management script..."
    create_management_script

    print_summary

    read -p "Open management menu now? [Y/n] " open_menu < /dev/tty || true
    if [[ ! "$open_menu" =~ ^[Nn]$ ]]; then
        "$INSTALL_DIR/conduit" menu
    fi
}
#
# REACHED END OF SCRIPT - VERSION 1.1
# ###############################################################################
main "$@"


