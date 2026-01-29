get_container_stats() {
    # Get CPU and RAM usage across all conduit containers
    # Returns: "CPU_PERCENT RAM_USAGE"
    # Single docker stats call for all containers at once
    local names=""
    for i in $(seq 1 $CONTAINER_COUNT); do
        names+=" $(get_container_name $i)"
    done
    local all_stats=$(docker stats --no-stream --format "{{.CPUPerc}} {{.MemUsage}}" $names 2>/dev/null)
    if [ -z "$all_stats" ]; then
        echo "0% 0MiB"
    elif [ "$CONTAINER_COUNT" -le 1 ]; then
        echo "$all_stats"
    else
        # Single awk to aggregate all container stats at once
        echo "$all_stats" | awk '{
            # CPU: strip % and sum
            cpu = $1; gsub(/%/, "", cpu); total_cpu += cpu + 0
            # Memory used: convert to MiB and sum
            mem = $2; gsub(/[^0-9.]/, "", mem); mem += 0
            if ($2 ~ /GiB/) mem *= 1024
            else if ($2 ~ /KiB/) mem /= 1024
            total_mem += mem
            # Memory limit: take first one
            if (mem_limit == "") mem_limit = $4
            found = 1
        } END {
            if (!found) { print "0% 0MiB"; exit }
            if (total_mem >= 1024) mem_display = sprintf("%.2fGiB", total_mem/1024)
            else mem_display = sprintf("%.1fMiB", total_mem)
            printf "%.2f%% %s / %s\n", total_cpu, mem_display, mem_limit
        }'
    fi
}

get_cpu_cores() {
    local cores=1
    if command -v nproc &>/dev/null; then
        cores=$(nproc)
    elif [ -f /proc/cpuinfo ]; then
        cores=$(grep -c ^processor /proc/cpuinfo)
    fi
    if [ -z "$cores" ] || [ "$cores" -lt 1 ] 2>/dev/null; then echo 1; else echo "$cores"; fi
}

get_system_stats() {
    # Get System CPU (Live Delta) and RAM
    # Returns: "CPU_PERCENT RAM_USED RAM_TOTAL RAM_PCT"
    
    # 1. System CPU (Stateful Average)
    local sys_cpu="0%"
    local cpu_tmp="/tmp/conduit_cpu_state"
    
    if [ -f /proc/stat ]; then
        read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
        local total_curr=$((user + nice + system + idle + iowait + irq + softirq + steal))
        local work_curr=$((user + nice + system + irq + softirq + steal))
        
        if [ -f "$cpu_tmp" ]; then
            read -r total_prev work_prev < "$cpu_tmp"
            local total_delta=$((total_curr - total_prev))
            local work_delta=$((work_curr - work_prev))
            
            if [ "$total_delta" -gt 0 ]; then
                local cpu_usage=$(awk -v w="$work_delta" -v t="$total_delta" 'BEGIN { printf "%.1f", w * 100 / t }' 2>/dev/null || echo 0)
                sys_cpu="${cpu_usage}%"
            fi
        else
            sys_cpu="Calc..." # First run calibration
        fi
        
        # Save current state for next run
        echo "$total_curr $work_curr" > "$cpu_tmp"
    else
        sys_cpu="N/A"
    fi
    
    # 2. System RAM (Used, Total, Percentage)
    local sys_ram_used="N/A"
    local sys_ram_total="N/A"
    local sys_ram_pct="N/A"
    
    if command -v free &>/dev/null; then
        # Single free -m call: MiB values for percentage + display
        local free_out=$(free -m 2>/dev/null)
        if [ -n "$free_out" ]; then
            read -r sys_ram_used sys_ram_total sys_ram_pct <<< $(echo "$free_out" | awk '/^Mem:/{
                used_mb=$3; total_mb=$2
                pct = (total_mb > 0) ? (used_mb/total_mb)*100 : 0
                if (total_mb >= 1024) { total_str=sprintf("%.1fGiB", total_mb/1024) } else { total_str=sprintf("%.1fMiB", total_mb) }
                if (used_mb >= 1024) { used_str=sprintf("%.1fGiB", used_mb/1024) } else { used_str=sprintf("%.1fMiB", used_mb) }
                printf "%s %s %.2f%%", used_str, total_str, pct
            }')
        fi
    fi
    
    echo "$sys_cpu $sys_ram_used $sys_ram_total $sys_ram_pct"
}

