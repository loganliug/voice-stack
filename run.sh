#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Resolve script directory (host & container safe)
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If run.sh is inside a subdirectory, adjust PROJECT_ROOT accordingly
PROJECT_ROOT="$SCRIPT_DIR"
# PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# =============================================================================
# VTN vendor library path
# =============================================================================
VTN_LIB_DIR="$PROJECT_ROOT/crates/vtn/vtn-sys/vendor/linaro7.5.0_x64_release"

if [[ ! -d "$VTN_LIB_DIR" ]]; then
    echo "[ERROR] VTN library directory not found: $VTN_LIB_DIR" >&2
    exit 1
fi

# =============================================================================
# Export runtime environment (ALL centralized here)
# =============================================================================

# Dynamic linker
export LD_LIBRARY_PATH="$VTN_LIB_DIR:${LD_LIBRARY_PATH:-}"

# JACK client behavior
export JACK_DEFAULT_SERVER="system"
export JACK_START_SERVER="0"
export JACK_NO_AUDIO_RESERVATION="1"

# =============================================================================
# Debug output (keep this!)
# =============================================================================
echo "[INFO] SCRIPT_DIR              = $SCRIPT_DIR"
echo "[INFO] PROJECT_ROOT            = $PROJECT_ROOT"
echo "[INFO] LD_LIBRARY_PATH         = $LD_LIBRARY_PATH"
echo "[INFO] JACK_DEFAULT_SERVER     = $JACK_DEFAULT_SERVER"
echo "[INFO] JACK_START_SERVER       = $JACK_START_SERVER"
echo "[INFO] JACK_NO_AUDIO_RESERVATION= $JACK_NO_AUDIO_RESERVATION"


# ============================================================================
# Configuration
# ============================================================================
AIUI_BIN="$PROJECT_ROOT/asrd"
VTN_BIN="$PROJECT_ROOT/znoise"
PLAYCTL_BIN="$PROJECT_ROOT/playctl"

MAX_WAIT_ATTEMPTS=30
WAIT_INTERVAL=1
MAX_CONNECT_RETRIES=5

# ============================================================================
# JACK client environment
# ============================================================================
export JACK_NO_AUDIO_RESERVATION=1
export JACK_START_SERVER=0
export JACK_DEFAULT_SERVER=system

# ============================================================================
# Logging helpers
# ============================================================================
log_i()   { echo -e "[INFO] $*"; }
log_w()   { echo -e "[WARN] $*"; }
log_e()   { echo -e "[ERROR] $*"; }
log_ok()  { echo -e "[OK] $*"; }

# ============================================================================
# Helper functions
# ============================================================================
wait_for_jack() {
    log_i "Waiting for system JACK server..."
    for ((i=1;i<=MAX_WAIT_ATTEMPTS;i++)); do
        if jack_lsp 2>/dev/null | grep -q "^system:"; then
            log_ok "Connected to JACK server"
            return 0
        fi
        log_w "JACK not ready ($i/$MAX_WAIT_ATTEMPTS)"
        sleep "$WAIT_INTERVAL"
    done
    log_e "Cannot connect to system JACK"
    return 1
}

wait_port() {
    local port="$1"
    for ((i=1;i<=MAX_WAIT_ATTEMPTS;i++)); do
        jack_lsp 2>/dev/null | grep -qx "$port" && return 0
        sleep "$WAIT_INTERVAL"
    done
    log_w "Port not found: $port"
    return 1
}

jack_connect_retry() {
    local src="$1" dst="$2"
    for ((i=1;i<=MAX_CONNECT_RETRIES;i++)); do
        jack_connect "$src" "$dst" 2>/dev/null && {
            log_ok "Connected $src -> $dst"
            return 0
        }
        sleep 1
    done
    log_w "Failed to connect $src -> $dst"
}

stop_all() {
    log_i "Stopping all services..."
    pkill -f "$VTN_BIN" 2>/dev/null || true
    pkill -f "$AIUI_BIN" 2>/dev/null || true
    pkill -f "$PLAYCTL_BIN" 2>/dev/null || true
    log_ok "All services stopped"
}

# ============================================================================
# JACK routing
# ============================================================================
connect_routing() {
    wait_port "vtn:input_1"
    wait_port "vtn:input_2"
    wait_port "vtn:output"
    wait_port "aiui:input"

    jack_connect_retry system:capture_1 vtn:input_1
    jack_connect_retry system:capture_2 vtn:input_2
    jack_connect_retry vtn:output aiui:input

    wait_port "playctl:output_left"
    wait_port "playctl:output_right"

    jack_connect_retry playctl:output_left system:playback_1
    jack_connect_retry playctl:output_right system:playback_2

    wait_port "vtn:reference_1"
    wait_port "vtn:reference_2"

    jack_connect_retry playctl:output_left vtn:reference_1
    jack_connect_retry playctl:output_right vtn:reference_2
}

# ============================================================================
# Start all services in Docker-friendly foreground mode
# ============================================================================
start() {
    wait_for_jack
    log_i "Starting services..."

    # Launch services in background — logs go directly to Docker stdout
    "$VTN_BIN" &
    VTN_PID=$!
    "$AIUI_BIN" &
    AIUI_PID=$!
    "$PLAYCTL_BIN" &
    PLAYCTL_PID=$!

    # Give services a moment before JACK routing
    sleep 2
    connect_routing
    log_ok "All services started"

    # Wait for any service to exit
    wait -n $VTN_PID $AIUI_PID $PLAYCTL_PID
    EXIT_STATUS=$?

    log_e "One of the services exited! Stopping remaining services..."
    stop_all
    exit $EXIT_STATUS
}

# ============================================================================
# Signal handling
# ============================================================================
trap stop_all SIGINT SIGTERM

# ============================================================================
# Script entry point
# ============================================================================
case "${1:-start}" in
    start) start ;;
    stop) stop_all ;;
    restart) stop_all; sleep 1; start ;;
    *) echo "Usage: $0 {start|stop|restart}" ;;
esac
