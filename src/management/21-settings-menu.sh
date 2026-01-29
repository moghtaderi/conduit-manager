show_settings_menu() {
    local redraw=true
    while true; do
        if [ "$redraw" = true ]; then
            clear
            print_header

            echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
            echo -e "${CYAN}  SETTINGS & TOOLS${NC}"
            echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
            echo -e "  1. ⚙️  Change settings (max-clients, bandwidth)"
            echo -e "  2. 📊 Set data usage cap"
            echo ""
            echo -e "  3. 💾 Backup node key"
            echo -e "  4. 📥 Restore node key"
            echo -e "  5. 🩺 Health check"
            echo ""
            echo -e "  6. 📱 Show QR Code & Conduit ID"
            echo -e "  7. ℹ️  Version info"
            echo -e "  8. 📖 About Conduit"
            echo ""
            echo -e "  9. 🔄 Reset tracker data"
            echo -e "  u. 🗑️  Uninstall"
            echo -e "  0. ← Back to main menu"
            echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
            echo ""
            redraw=false
        fi

        read -p "  Enter choice: " choice < /dev/tty || { return; }

        case "$choice" in
            1)
                change_settings
                redraw=true
                ;;
            2)
                set_data_cap
                read -n 1 -s -r -p "Press any key to return..." < /dev/tty || true
                redraw=true
                ;;
            3)
                backup_key
                read -n 1 -s -r -p "Press any key to return..." < /dev/tty || true
                redraw=true
                ;;
            4)
                restore_key
                read -n 1 -s -r -p "Press any key to return..." < /dev/tty || true
                redraw=true
                ;;
            5)
                health_check
                read -n 1 -s -r -p "Press any key to return..." < /dev/tty || true
                redraw=true
                ;;
            6)
                show_qr_code
                redraw=true
                ;;
            7)
                show_version
                read -n 1 -s -r -p "Press any key to return..." < /dev/tty || true
                redraw=true
                ;;
            8)
                show_about
                redraw=true
                ;;
            9)
                echo ""
                while true; do
                    read -p "Reset tracker and delete all stats data? (y/n): " confirm < /dev/tty || true
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        echo "Stopping tracker service..."
                        stop_tracker_service 2>/dev/null || true
                        echo "Deleting tracker data..."
                        rm -rf /opt/conduit/traffic_stats 2>/dev/null || true
                        rm -f /opt/conduit/conduit-tracker.sh 2>/dev/null || true
                        echo "Restarting tracker service..."
                        regenerate_tracker_script
                        setup_tracker_service
                        echo -e "${GREEN}Tracker data has been reset.${NC}"
                        break
                    elif [[ "$confirm" =~ ^[Nn]$ ]]; then
                        echo "Cancelled."
                        break
                    else
                        echo "Please enter y or n."
                    fi
                done
                read -n 1 -s -r -p "Press any key to return..." < /dev/tty || true
                redraw=true
                ;;
            u)
                uninstall_all
                exit 0
                ;;
            0)
                return
                ;;
            "")
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                ;;
        esac
    done
}

