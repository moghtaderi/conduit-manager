verify_image_digest() {
    local expected="$1"
    local image="$2"

    log_info "Verifying image integrity..."

    local actual=$(docker inspect --format='{{index .RepoDigests 0}}' "$image" 2>/dev/null | grep -o 'sha256:[a-f0-9]*')

    if [ -z "$actual" ]; then
        log_warn "Could not verify image digest (image may not have RepoDigests)"
        return 0
    fi

    if [ "$actual" != "$expected" ]; then
        log_error "Image digest mismatch!"
        log_error "  Expected: $expected"
        log_error "  Got:      $actual"
        log_error "This could indicate a compromised image. Aborting."
        return 1
    fi

    log_success "Image digest verified: ${actual:0:20}..."
    return 0
}

