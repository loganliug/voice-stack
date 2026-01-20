#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Environment paths
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
BIN_DIR="$PROJECT_ROOT/target/aarch64-unknown-linux-gnu/release"
VTN_LIB_DIR="$PROJECT_ROOT/crates/vtn/vtn-sys/vendor/linaro7.5.0_x64_release"

[[ -d "$VTN_LIB_DIR" ]] || { echo "[ERROR] VTN library not found: $VTN_LIB_DIR"; exit 1; }

export LD_LIBRARY_PATH="$VTN_LIB_DIR:${LD_LIBRARY_PATH:-}"
export JACK_DEFAULT_SERVER="system"
export JACK_START_SERVER="0"
export JACK_NO_AUDIO_RESERVATION="1"

AIUI_BIN="$BIN_DIR/asrd"
VTN_BIN="$BIN_DIR/znoise"
PLAYCTL_BIN="$BIN_DIR/playctl"

# =============================================================================
# Logging helpers
# =============================================================================
log_i()  { echo "[INFO] $*"; }
log_w()  { echo "[WARN] $*"; }
log_e()  { echo "[ERROR] $*"; }
log_ok() { echo "[OK] $*"; }

# =============================================================================
# General settings for JACK and waiting
# =============================================================================
WAIT_INTERVAL=1
MAX_WAIT_ATTEMPTS=30
CONNECT_TIMEOUT=30  # total timeout in seconds for connect_routing

# =============================================================================
# Wait for JACK system server
# =============================================================================
wait_for_jack() {
    log_i "Waiting for system JACK server..."
    for ((i=1;i<=MAX_WAIT_ATTEMPTS;i++)); do
        if jack_lsp 2>/dev/null | grep -q "^system:"; then
            log_ok "Connected to JACK"
            return 0
        fi
        sleep "$WAIT_INTERVAL"
    done
    log_e "Cannot connect to JACK server"
    return 1
}

# =============================================================================
# JACK connection with retry
# =============================================================================
jack_connect_retry() {
    local src=$1 dst=$2
    for ((i=1;i<=5;i++)); do
        if jack_connect "$src" "$dst" 2>/dev/null; then
            log_ok "Connected $src -> $dst"
            return 0
        fi
        sleep 1
    done
    log_w "Failed to connect $src -> $dst"
    return 1
}

# =============================================================================
# Connect routing (foreground) with total timeout
# =============================================================================
connect_routing() {
    local ports=( \
        "vtn:input_1" \
        "vtn:input_2" \
        "vtn:reference_1" \
        "vtn:reference_2" \
        "vtn:output" \
        "aiui:input" \
        "playctl:output_left" \
        "playctl:output_right" \
    )

    log_i "Waiting for JACK ports (total timeout ${CONNECT_TIMEOUT}s)..."
    local start_time=$(date +%s)
    local all_ready=1

    for port in "${ports[@]}"; do
        while true; do
            if jack_lsp 2>/dev/null | grep -qx "$port"; then
                log_ok "Port ready: $port"
                break
            fi
            local now=$(date +%s)
            local elapsed=$(( now - start_time ))
            if (( elapsed >= CONNECT_TIMEOUT )); then
                log_w "Timeout waiting for port: $port"
                all_ready=0
                break
            fi
            sleep "$WAIT_INTERVAL"
        done
    done

    if (( all_ready == 0 )); then
        log_e "Some ports were not ready within timeout!"
        return 1  # critical failure
    else
        log_ok "All ports ready"
    fi

    # Perform JACK connections
    jack_connect_retry system:capture_1 vtn:input_1 
    jack_connect_retry system:capture_2 vtn:input_2
    jack_connect_retry vtn:output aiui:input
    jack_connect_retry playctl:output_left system:playback_1
    jack_connect_retry playctl:output_right system:playback_2
    jack_connect_retry playctl:output_left vtn:reference_1
    jack_connect_retry playctl:output_right vtn:reference_2

    log_ok "Routing completed"
    return 0
}

# =============================================================================
# Service startup functions
# =============================================================================
start_vtn() {
    log_i "Starting VTN service..."
    "$VTN_BIN" &
    VTN_PID=$!
}

start_aiui() {
    log_i "Starting AIUI service..."
    "$AIUI_BIN" &
    AIUI_PID=$!
}

start_playctl() {
    log_i "Starting Playctl service..."
    "$PLAYCTL_BIN" &
    PLAYCTL_PID=$!
}

# =============================================================================
# Start all services and manage lifecycle
# =============================================================================
start() {
    wait_for_jack

    start_vtn
    start_aiui
    start_playctl

    sleep 2

    # Run routing in foreground: must succeed
    if ! connect_routing; then
        log_e "Routing failed, stopping all services..."
        pkill -P $$ 2>/dev/null || true
        exit 1
    fi
    log_ok "Routing successful"

    # Wait for any service to exit
    wait -n $VTN_PID $AIUI_PID $PLAYCTL_PID
    EXIT_STATUS=$?
    log_e "One service exited, stopping remaining..."
    pkill -P $$ 2>/dev/null || true
    exit $EXIT_STATUS
}

# =============================================================================
# Signal handling for graceful shutdown
# =============================================================================
trap 'log_i "Terminating all child processes"; pkill -P $$ 2>/dev/null || true' SIGINT SIGTERM


# =============================================================================
# Script entry point
# =============================================================================
start
