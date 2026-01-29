install_package() {
    local package="$1"
    log_info "Installing $package..."
    
    case "$PKG_MANAGER" in
        apt)
            apt-get update -q || log_warn "apt-get update failed, attempting install anyway..."
            if apt-get install -y -q "$package"; then
                log_success "$package installed successfully"
            else
                log_error "Failed to install $package"
                return 1
            fi
            ;;
        dnf)
            if dnf install -y -q "$package"; then
                log_success "$package installed successfully"
            else
                log_error "Failed to install $package"
                return 1
            fi
            ;;
        yum)
            if yum install -y -q "$package"; then
                log_success "$package installed successfully"
            else
                log_error "Failed to install $package"
                return 1
            fi
            ;;
        pacman)
            if pacman -Sy --noconfirm "$package"; then
                log_success "$package installed successfully"
            else
                log_error "Failed to install $package"
                return 1
            fi
            ;;
        zypper)
            if zypper install -y -n "$package"; then
                log_success "$package installed successfully"
            else
                log_error "Failed to install $package"
                return 1
            fi
            ;;
        apk)
            if apk add --no-cache "$package"; then
                log_success "$package installed successfully"
            else
                log_error "Failed to install $package"
                return 1
            fi
            ;;
        *)
            log_warn "Unknown package manager. Please install $package manually."
            return 1
            ;;
    esac
}

check_dependencies() {
    if [ "$OS_FAMILY" = "alpine" ]; then
        if ! command -v bash &>/dev/null; then
            log_info "Installing bash..."
            apk add --no-cache bash 2>/dev/null
        fi
    fi
    
    if ! command -v curl &>/dev/null; then
        install_package curl || log_warn "Could not install curl automatically"
    fi
    
    if ! command -v awk &>/dev/null; then
        case "$PKG_MANAGER" in
            apt) install_package gawk || log_warn "Could not install gawk" ;;
            apk) install_package gawk || log_warn "Could not install gawk" ;;
            *) install_package awk || log_warn "Could not install awk" ;;
        esac
    fi
    
    if ! command -v free &>/dev/null; then
        case "$PKG_MANAGER" in
            apt|dnf|yum) install_package procps || log_warn "Could not install procps" ;;
            pacman) install_package procps-ng || log_warn "Could not install procps" ;;
            zypper) install_package procps || log_warn "Could not install procps" ;;
            apk) install_package procps || log_warn "Could not install procps" ;;
        esac
    fi

    if ! command -v tput &>/dev/null; then
        case "$PKG_MANAGER" in
            apt) install_package ncurses-bin || log_warn "Could not install ncurses-bin" ;;
            apk) install_package ncurses || log_warn "Could not install ncurses" ;;
            *) install_package ncurses || log_warn "Could not install ncurses" ;;
        esac
    fi

    if ! command -v tcpdump &>/dev/null; then
        install_package tcpdump || log_warn "Could not install tcpdump automatically"
    fi

    # GeoIP (geoiplookup or mmdblookup fallback)
    if ! command -v geoiplookup &>/dev/null && ! command -v mmdblookup &>/dev/null; then
        case "$PKG_MANAGER" in
            apt)
                install_package geoip-bin || log_warn "Could not install geoip-bin"
                install_package geoip-database || log_warn "Could not install geoip-database"
                ;;
            dnf|yum)
                if ! rpm -q epel-release &>/dev/null; then
                    $PKG_MANAGER install -y epel-release &>/dev/null || true
                fi
                if ! install_package GeoIP 2>/dev/null; then
                    # AL2023/Fedora: fallback to libmaxminddb
                    log_info "Legacy GeoIP not available, trying libmaxminddb..."
                    install_package libmaxminddb || log_warn "Could not install libmaxminddb"
                    if [ ! -f /usr/share/GeoIP/GeoLite2-Country.mmdb ] && [ ! -f /var/lib/GeoIP/GeoLite2-Country.mmdb ]; then
                        mkdir -p /usr/share/GeoIP
                        local mmdb_url="https://raw.githubusercontent.com/P3TERX/GeoLite.mmdb/download/GeoLite2-Country.mmdb"
                        curl -sL "$mmdb_url" -o /usr/share/GeoIP/GeoLite2-Country.mmdb 2>/dev/null || \
                            log_warn "Could not download GeoLite2-Country.mmdb"
                    fi
                fi
                ;;
            pacman) install_package geoip || log_warn "Could not install geoip." ;;
            zypper) install_package GeoIP || log_warn "Could not install GeoIP." ;;
            apk) install_package geoip || log_warn "Could not install geoip." ;;
            *) log_warn "Could not install geoiplookup automatically" ;;
        esac
    fi

    if ! command -v qrencode &>/dev/null; then
        install_package qrencode || log_warn "Could not install qrencode automatically"
    fi
}

