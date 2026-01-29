MANAGEMENT

    # Patch the INSTALL_DIR in the generated script
    sed -i "s#REPLACE_ME_INSTALL_DIR#$INSTALL_DIR#g" "$INSTALL_DIR/conduit"

    chmod +x "$INSTALL_DIR/conduit"
    # Force create symlink
    rm -f /usr/local/bin/conduit 2>/dev/null || true
    ln -s "$INSTALL_DIR/conduit" /usr/local/bin/conduit

    log_success "Management script installed: conduit"
}
