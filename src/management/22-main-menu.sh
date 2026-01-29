show_menu() {
    # Auto-fix conduit.service if it's in failed state
    if command -v systemctl &>/dev/null; then
        local svc_state=$(systemctl is-active conduit.service 2>/dev/null)
        if [ "$svc_state" = "failed" ]; then
            systemctl reset-failed conduit.service 2>/dev/null || true
            systemctl restart conduit.service 2>/dev/null || true
        fi
    fi

    # Auto-start tracker if not running and containers are up
    if ! is_tracker_active; then
        local any_running=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c "^conduit")
        if [ "${any_running:-0}" -gt 0 ]; then
            setup_tracker_service
        fi
    fi

    local redraw=true
    while true; do
        if [ "$redraw" = true ]; then
            clear
            print_header

            echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
            echo -e "${CYAN}  MAIN MENU${NC}"
            echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
            echo -e "  1. 📈 View status dashboard"
            echo -e "  2. 📊 Live connection stats"
            echo -e "  3. 📋 View logs"
            echo -e "  4. 🌍 Live peers by country"
            echo ""
            echo -e "  5. ▶️  Start Conduit"
            echo -e "  6. ⏹️  Stop Conduit"
            echo -e "  7. 🔁 Restart Conduit"
            echo -e "  8. 🔄 Update Conduit"
            echo ""
            echo -e "  9. ⚙️  Settings & Tools"
            echo -e "  c. 📦 Manage containers"
            echo -e "  a. 📊 Advanced stats"
            echo -e "  i. ℹ️  Info & Help"
            echo -e "  0. 🚪 Exit"
            echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
            echo ""
            redraw=false
        fi

        read -p "  Enter choice: " choice < /dev/tty || { echo "Input error. Exiting."; exit 1; }

        case "$choice" in
            1)
                show_dashboard
                redraw=true
                ;;
            2)
                show_live_stats
                redraw=true
                ;;
            3)
                show_logs
                redraw=true
                ;;
            4)
                show_peers
                redraw=true
                ;;
            5)
                start_conduit
                read -n 1 -s -r -p "Press any key to return..." < /dev/tty || true
                redraw=true
                ;;
            6)
                stop_conduit
                read -n 1 -s -r -p "Press any key to return..." < /dev/tty || true
                redraw=true
                ;;
            7)
                restart_conduit
                read -n 1 -s -r -p "Press any key to return..." < /dev/tty || true
                redraw=true
                ;;
            8)
                update_conduit
                read -n 1 -s -r -p "Press any key to return..." < /dev/tty || true
                redraw=true
                ;;
            9)
                show_settings_menu
                redraw=true
                ;;
            c)
                manage_containers
                redraw=true
                ;;
            a)
                show_advanced_stats
                redraw=true
                ;;
            i)
                show_info_menu
                redraw=true
                ;;
            0)
                echo "Exiting."
                exit 0
                ;;
            "")
                ;;
            *)
                echo -e "${RED}Invalid choice: ${NC}${YELLOW}$choice${NC}"
                ;;
        esac
    done
}

# Info hub - sub-page menu
