is_tracker_active() {
    if command -v systemctl &>/dev/null; then
        systemctl is-active conduit-tracker.service &>/dev/null
        return $?
    fi
    # Fallback: check if tracker process is running
    pgrep -f "conduit-tracker.sh" &>/dev/null
    return $?
}

# Generate the background tracker script
regenerate_tracker_script() {
    local tracker_script="$INSTALL_DIR/conduit-tracker.sh"
    local persist_dir="$INSTALL_DIR/traffic_stats"
    mkdir -p "$INSTALL_DIR" "$persist_dir"

    cat > "$tracker_script" << 'TRACKER_SCRIPT'
#!/bin/bash
# Psiphon Conduit Background Tracker
set -u

INSTALL_DIR="/opt/conduit"
PERSIST_DIR="/opt/conduit/traffic_stats"
mkdir -p "$PERSIST_DIR"
STATS_FILE="$PERSIST_DIR/cumulative_data"
IPS_FILE="$PERSIST_DIR/cumulative_ips"
SNAPSHOT_FILE="$PERSIST_DIR/tracker_snapshot"
C_START_FILE="$PERSIST_DIR/container_start"
GEOIP_CACHE="$PERSIST_DIR/geoip_cache"

# Detect local IPs
get_local_ips() {
    ip -4 addr show 2>/dev/null | awk '/inet /{split($2,a,"/"); print a[1]}' | tr '\n' '|'
    echo ""
}

# GeoIP lookup with file-based cache
geo_lookup() {
    local ip="$1"
    # Check cache
    if [ -f "$GEOIP_CACHE" ]; then
        local cached=$(grep "^${ip}|" "$GEOIP_CACHE" 2>/dev/null | head -1 | cut -d'|' -f2)
        if [ -n "$cached" ]; then
            echo "$cached"
            return
        fi
    fi
    local country=""
    if command -v geoiplookup &>/dev/null; then
        country=$(geoiplookup "$ip" 2>/dev/null | awk -F: '/Country Edition/{print $2}' | sed 's/^ *//' | cut -d, -f2- | sed 's/^ *//')
    elif command -v mmdblookup &>/dev/null; then
        local mmdb=""
        for f in /usr/share/GeoIP/GeoLite2-Country.mmdb /var/lib/GeoIP/GeoLite2-Country.mmdb; do
            [ -f "$f" ] && mmdb="$f" && break
        done
        if [ -n "$mmdb" ]; then
            country=$(mmdblookup --file "$mmdb" --ip "$ip" country names en 2>/dev/null | grep -o '"[^"]*"' | tr -d '"')
        fi
    fi
    [ -z "$country" ] && country="Unknown"
    # Cache it (limit cache size)
    if [ -f "$GEOIP_CACHE" ]; then
        local cache_lines=$(wc -l < "$GEOIP_CACHE" 2>/dev/null || echo 0)
        if [ "$cache_lines" -gt 10000 ]; then
            tail -5000 "$GEOIP_CACHE" > "$GEOIP_CACHE.tmp" && mv "$GEOIP_CACHE.tmp" "$GEOIP_CACHE"
        fi
    fi
    echo "${ip}|${country}" >> "$GEOIP_CACHE"
    echo "$country"
}

# Check for container restart — reset data if restarted
container_start=$(docker inspect --format='{{.State.StartedAt}}' conduit 2>/dev/null | cut -d'.' -f1)
stored_start=""
[ -f "$C_START_FILE" ] && stored_start=$(cat "$C_START_FILE" 2>/dev/null)
if [ "$container_start" != "$stored_start" ]; then
    echo "$container_start" > "$C_START_FILE"
    # Backup cumulative data before reset
    if [ -s "$STATS_FILE" ] || [ -s "$IPS_FILE" ]; then
        echo "[TRACKER] Container restart detected — backing up tracker data"
        [ -s "$STATS_FILE" ] && cp "$STATS_FILE" "$PERSIST_DIR/cumulative_data.bak"
        [ -s "$IPS_FILE" ] && cp "$IPS_FILE" "$PERSIST_DIR/cumulative_ips.bak"
        [ -s "$GEOIP_CACHE" ] && cp "$GEOIP_CACHE" "$PERSIST_DIR/geoip_cache.bak"
    fi
    rm -f "$STATS_FILE" "$IPS_FILE" "$SNAPSHOT_FILE"
    # Restore cumulative data (keep historical totals across restarts)
    if [ -f "$PERSIST_DIR/cumulative_data.bak" ]; then
        cp "$PERSIST_DIR/cumulative_data.bak" "$STATS_FILE"
        cp "$PERSIST_DIR/cumulative_ips.bak" "$IPS_FILE" 2>/dev/null
        echo "[TRACKER] Tracker data restored from backup"
    fi
fi
touch "$STATS_FILE" "$IPS_FILE"

# Detect tcpdump and awk paths
TCPDUMP_BIN=$(command -v tcpdump 2>/dev/null || echo "tcpdump")
AWK_BIN=$(command -v gawk 2>/dev/null || command -v awk 2>/dev/null || echo "awk")

# Detect local IP
LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
[ -z "$LOCAL_IP" ] && LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

# Batch process: resolve GeoIP + merge into cumulative files in bulk
process_batch() {
    local batch="$1"
    local resolved="$PERSIST_DIR/resolved_batch"
    local geo_map="$PERSIST_DIR/geo_map"

    # Step 1: Extract unique IPs and bulk-resolve GeoIP
    # Read cache once, resolve uncached, produce ip|country mapping
    $AWK_BIN -F'|' '{print $2}' "$batch" | sort -u > "$PERSIST_DIR/batch_ips"

    # Build geo mapping: read cache + resolve missing
    > "$geo_map"
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        country=""
        if [ -f "$GEOIP_CACHE" ]; then
            country=$(grep "^${ip}|" "$GEOIP_CACHE" 2>/dev/null | head -1 | cut -d'|' -f2)
        fi
        if [ -z "$country" ]; then
            country=$(geo_lookup "$ip")
        fi
        # Strip country code prefix (e.g. "US, United States" -> "United States")
        country=$(echo "$country" | sed 's/^[A-Z][A-Z], //')
        # Normalize
        case "$country" in
            *Iran*) country="Iran - #FreeIran" ;;
            *Moldova*) country="Moldova" ;;
            *Korea*Republic*|*"South Korea"*) country="South Korea" ;;
            *"Russian Federation"*|*Russia*) country="Russia" ;;
            *"Taiwan"*) country="Taiwan" ;;
            *"Venezuela"*) country="Venezuela" ;;
            *"Bolivia"*) country="Bolivia" ;;
            *"Tanzania"*) country="Tanzania" ;;
            *"Viet Nam"*|*Vietnam*) country="Vietnam" ;;
            *"Syrian Arab Republic"*) country="Syria" ;;
        esac
        echo "${ip}|${country}" >> "$geo_map"
    done < "$PERSIST_DIR/batch_ips"

    # Step 2: Single awk pass — merge batch into cumulative_data + write snapshot
    $AWK_BIN -F'|' -v snap="$SNAPSHOT_FILE" '
        BEGIN { OFMT = "%.0f"; CONVFMT = "%.0f" }
        FILENAME == ARGV[1] { geo[$1] = $2; next }
        FILENAME == ARGV[2] { existing[$1] = $2 "|" $3; next }
        FILENAME == ARGV[3] {
            dir = $1; ip = $2; bytes = $3 + 0
            c = geo[ip]
            if (c == "") c = "Unknown"
            if (dir == "FROM") from_bytes[c] += bytes
            else to_bytes[c] += bytes
            # Also collect snapshot lines
            print dir "|" c "|" bytes "|" ip > snap
            next
        }
        END {
            # Merge existing + new
            for (c in existing) {
                split(existing[c], v, "|")
                f = v[1] + 0; t = v[2] + 0
                f += from_bytes[c] + 0
                t += to_bytes[c] + 0
                print c "|" f "|" t
                delete from_bytes[c]
                delete to_bytes[c]
            }
            # New countries not in existing
            for (c in from_bytes) {
                f = from_bytes[c] + 0
                t = to_bytes[c] + 0
                print c "|" f "|" t
                delete to_bytes[c]
            }
            for (c in to_bytes) {
                print c "|0|" to_bytes[c] + 0
            }
        }
    ' "$geo_map" "$STATS_FILE" "$batch" > "$STATS_FILE.tmp" && mv "$STATS_FILE.tmp" "$STATS_FILE"

    # Step 3: Single awk pass — merge batch IPs into cumulative_ips
    $AWK_BIN -F'|' '
        FILENAME == ARGV[1] { geo[$1] = $2; next }
        FILENAME == ARGV[2] { seen[$0] = 1; print; next }
        FILENAME == ARGV[3] {
            ip = $2; c = geo[ip]
            if (c == "") c = "Unknown"
            key = c "|" ip
            if (!(key in seen)) { seen[key] = 1; print key }
        }
    ' "$geo_map" "$IPS_FILE" "$batch" > "$IPS_FILE.tmp" && mv "$IPS_FILE.tmp" "$IPS_FILE"

    rm -f "$PERSIST_DIR/batch_ips" "$geo_map" "$resolved"
}

# Main capture loop: tcpdump -> awk -> batch process
LAST_BACKUP=0
while true; do
    BATCH_FILE="$PERSIST_DIR/batch_tmp"
    > "$BATCH_FILE"

    while IFS= read -r line; do
        if [ "$line" = "SYNC_MARKER" ]; then
            # Process entire batch at once
            if [ -s "$BATCH_FILE" ]; then
                > "$SNAPSHOT_FILE"
                process_batch "$BATCH_FILE"
            fi
            > "$BATCH_FILE"
            # Periodic backup every 3 hours
            NOW=$(date +%s)
            if [ $((NOW - LAST_BACKUP)) -ge 10800 ]; then
                [ -s "$STATS_FILE" ] && cp "$STATS_FILE" "$PERSIST_DIR/cumulative_data.bak"
                [ -s "$IPS_FILE" ] && cp "$IPS_FILE" "$PERSIST_DIR/cumulative_ips.bak"
                LAST_BACKUP=$NOW
            fi
            continue
        fi
        echo "$line" >> "$BATCH_FILE"
    done < <($TCPDUMP_BIN -tt -l -ni any -n -q "(tcp or udp) and not port 22" 2>/dev/null | $AWK_BIN -v local_ip="$LOCAL_IP" '
    BEGIN { last_sync = 0; OFMT = "%.0f"; CONVFMT = "%.0f" }
    {
        # Parse timestamp
        ts = $1 + 0
        if (ts == 0) next

        # Find IP keyword and extract src/dst
        src = ""; dst = ""
        for (i = 1; i <= NF; i++) {
            if ($i == "IP") {
                sf = $(i+1)
                for (j = i+2; j <= NF; j++) {
                    if ($(j-1) == ">") {
                        df = $j
                        gsub(/:$/, "", df)
                        break
                    }
                }
                break
            }
        }
        # Extract IP from IP.port
        if (sf != "") { n=split(sf,p,"."); if(n>=4) src=p[1]"."p[2]"."p[3]"."p[4] }
        if (df != "") { n=split(df,p,"."); if(n>=4) dst=p[1]"."p[2]"."p[3]"."p[4] }

        # Get length
        len = 0
        for (i=1; i<=NF; i++) { if ($i=="length") { len=$(i+1)+0; break } }
        if (len==0) { for (i=NF; i>0; i--) { if ($i ~ /^[0-9]+$/) { len=$i+0; break } } }

        # Skip private IPs
        if (src ~ /^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|0\.|169\.254\.)/) src=""
        if (dst ~ /^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|0\.|169\.254\.)/) dst=""

        # Determine direction
        if (src == local_ip && dst != "" && dst != local_ip) {
            to[dst] += len
        } else if (dst == local_ip && src != "" && src != local_ip) {
            from[src] += len
        } else if (src != "" && src != local_ip) {
            from[src] += len
        } else if (dst != "" && dst != local_ip) {
            to[dst] += len
        }

        # Sync every 15 seconds
        if (last_sync == 0) last_sync = ts
        if (ts - last_sync >= 15) {
            for (ip in from) { if (from[ip] > 0) print "FROM|" ip "|" from[ip] }
            for (ip in to) { if (to[ip] > 0) print "TO|" ip "|" to[ip] }
            print "SYNC_MARKER"
            delete from; delete to; last_sync = ts; fflush()
        }
    }')

    # If tcpdump exits, wait and retry
    sleep 5
done
TRACKER_SCRIPT

    chmod +x "$tracker_script"
}

# Setup tracker systemd service
setup_tracker_service() {
    regenerate_tracker_script

    if command -v systemctl &>/dev/null; then
        cat > /etc/systemd/system/conduit-tracker.service << EOF
[Unit]
Description=Conduit Traffic Tracker
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/bin/bash $INSTALL_DIR/conduit-tracker.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable conduit-tracker.service 2>/dev/null || true
        systemctl restart conduit-tracker.service 2>/dev/null || true
    fi
}

# Stop tracker service
stop_tracker_service() {
    if command -v systemctl &>/dev/null; then
        systemctl stop conduit-tracker.service 2>/dev/null || true
    else
        pkill -f "conduit-tracker.sh" 2>/dev/null || true
    fi
}

# Advanced Statistics page with 15-second soft refresh
