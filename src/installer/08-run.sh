run_conduit() {
    local count=${CONTAINER_COUNT:-1}
    log_info "Starting Conduit ($count container(s))..."

    log_info "Pulling Conduit image ($CONDUIT_IMAGE)..."
    if ! docker pull "$CONDUIT_IMAGE"; then
        log_error "Failed to pull Conduit image. Check your internet connection."
        exit 1
    fi

    # Verify image integrity using SHA256 digest
    if ! verify_image_digest "$CONDUIT_IMAGE_DIGEST" "$CONDUIT_IMAGE"; then
        exit 1
    fi

    for i in $(seq 1 $count); do
        local cname="conduit"
        local vname="conduit-data"
        [ "$i" -gt 1 ] && cname="conduit-${i}" && vname="conduit-data-${i}"

        docker rm -f "$cname" 2>/dev/null || true

        # Ensure volume exists with correct permissions (uid 1000)
        docker volume create "$vname" 2>/dev/null || true
        docker run --rm -v "${vname}:/home/conduit/data" alpine \
            sh -c "chown -R 1000:1000 /home/conduit/data" 2>/dev/null || true

        docker run -d \
            --name "$cname" \
            --restart unless-stopped \
            --log-opt max-size=15m \
            --log-opt max-file=3 \
            -v "${vname}:/home/conduit/data" \
            --network host \
            "$CONDUIT_IMAGE" \
            start --max-clients "$MAX_CLIENTS" --bandwidth "$BANDWIDTH" --stats-file

        if [ $? -eq 0 ]; then
            log_success "$cname started"
        else
            log_error "Failed to start $cname"
        fi
    done

    sleep 3
    if docker ps | grep -q conduit; then
        if [ "$BANDWIDTH" == "-1" ]; then
            log_success "Settings: max-clients=$MAX_CLIENTS, bandwidth=Unlimited, containers=$count"
        else
            log_success "Settings: max-clients=$MAX_CLIENTS, bandwidth=${BANDWIDTH}Mbps, containers=$count"
        fi
    else
        log_error "Conduit failed to start"
        docker logs conduit 2>&1 | tail -10
        exit 1
    fi
}

