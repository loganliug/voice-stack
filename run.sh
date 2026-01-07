#!/usr/bin/env bash

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# Configuration
# ============================================================================

# Process Directories (all relative to /home/jackuser/app)
AIUI_DIR="."
VTN_DIR="."
PLAYCTL_DIR="."

# Binaries (relative to their respective directories)
AIUI_BIN="asrd"
VTN_BIN="znoise"
PLAYCTL_BIN="playctl"

# PID Files
AIUI_PID_FILE="/tmp/asrd.pid"
VTN_PID_FILE="/tmp/znoise.pid"
PLAYCTL_PID_FILE="/tmp/playctl.pid"

# Timeouts and retries
MAX_WAIT_ATTEMPTS=30
WAIT_INTERVAL=2
MAX_CONNECT_RETRIES=5

# Logging
export RUST_LOG=debug

# ============================================================================
# Color output for better readability
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# Helper Functions
# ============================================================================

is_running() {
    # $1: pid file
    # return 0 = running, 1 = not
    if [ -f "$1" ]; then
        PID=$(cat "$1")
        if kill -0 "$PID" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

wait_for_jack() {
    local attempt=0
    log_info "Waiting for JACK server..."
    
    while [ $attempt -lt $MAX_WAIT_ATTEMPTS ]; do
        if jack_lsp > /dev/null 2>&1; then
            log_success "JACK server is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        log_warn "JACK not ready (attempt $attempt/$MAX_WAIT_ATTEMPTS)"
        sleep $WAIT_INTERVAL
    done
    
    log_error "JACK server not available after $MAX_WAIT_ATTEMPTS attempts"
    return 1
}

wait_for_jack_port() {
    local port_name=$1
    local attempt=0
    log_info "Waiting for JACK port: $port_name"
    
    while [ $attempt -lt $MAX_WAIT_ATTEMPTS ]; do
        if jack_lsp 2>/dev/null | grep -q "^${port_name}$"; then
            log_success "Port $port_name is available"
            return 0
        fi
        attempt=$((attempt + 1))
        log_warn "Port $port_name not ready (attempt $attempt/$MAX_WAIT_ATTEMPTS)"
        sleep $WAIT_INTERVAL
    done
    
    log_error "Port $port_name not available"
    return 1
}

jack_connect_retry() {
    local source=$1
    local dest=$2
    local attempt=0
    
    log_info "Connecting $source -> $dest"
    
    while [ $attempt -lt $MAX_CONNECT_RETRIES ]; do
        if jack_connect "$source" "$dest" 2>/dev/null; then
            log_success "Connected: $source -> $dest"
            return 0
        fi
        attempt=$((attempt + 1))
        if [ $attempt -lt $MAX_CONNECT_RETRIES ]; then
            log_warn "Connection failed, retrying ($attempt/$MAX_CONNECT_RETRIES)..."
            sleep 1
        fi
    done
    
    log_error "Failed to connect $source -> $dest after $MAX_CONNECT_RETRIES attempts"
    return 1
}

# ============================================================================
# Service Start Functions
# ============================================================================

start_aiui() {
    log_info "Starting AIUI ASR service..."
    
    if is_running "$AIUI_PID_FILE"; then
        log_warn "AIUI already running (pid $(cat $AIUI_PID_FILE))"
        return 0
    fi
    
    if [ ! -f "$AIUI_DIR/$AIUI_BIN" ]; then
        log_error "AIUI binary not found: $AIUI_DIR/$AIUI_BIN"
        return 1
    fi
    
    # Start in aiui directory
    # cd "$AIUI_DIR"
    ./$AIUI_BIN > ../aiui.log 2>&1 &
    local PID=$!
    # cd ..
    
    echo $PID > $AIUI_PID_FILE
    log_success "AIUI started (PID: $PID)"
    sleep 2
    return 0
}

start_vtn() {
    log_info "Starting VTN ZNOISE service..."
    
    if is_running "$VTN_PID_FILE"; then
        log_warn "VTN already running (pid $(cat $VTN_PID_FILE))"
        return 0
    fi
    
    if [ ! -f "$VTN_DIR/$VTN_BIN" ]; then
        log_error "VTN binary not found: $VTN_DIR/$VTN_BIN"
        return 1
    fi
    
    # Start in vtn directory
    # cd "$VTN_DIR"
    ./$VTN_BIN > ../vtn.log 2>&1 &
    local PID=$!
    # cd ..
    
    echo $PID > $VTN_PID_FILE
    log_success "VTN started (PID: $PID)"
    sleep 2
    return 0
}

start_playctl() {
    log_info "Starting PLAYCTL service..."
    
    if is_running "$PLAYCTL_PID_FILE"; then
        log_warn "PLAYCTL already running (pid $(cat $PLAYCTL_PID_FILE))"
        return 0
    fi
    
    if [ ! -f "$PLAYCTL_DIR/$PLAYCTL_BIN" ]; then
        log_error "PLAYCTL binary not found: $PLAYCTL_DIR/$PLAYCTL_BIN"
        return 1
    fi
    
    # Start in playctl directory
    # cd "$PLAYCTL_DIR"
    ./$PLAYCTL_BIN > ../playctl.log 2>&1 &
    local PID=$!
    # cd ..
    
    echo $PID > $PLAYCTL_PID_FILE
    log_success "PLAYCTL started (PID: $PID)"
    sleep 2
    return 0
}

# ============================================================================
# Service Stop Functions
# ============================================================================

stop_aiui() {
    log_info "Stopping AIUI..."
    
    if is_running "$AIUI_PID_FILE"; then
        local PID=$(cat "$AIUI_PID_FILE")
        kill "$PID" 2>/dev/null && log_success "AIUI stopped (PID: $PID)" || log_warn "Failed to stop AIUI"
        sleep 1
        
        # Force kill if still running
        if kill -0 "$PID" 2>/dev/null; then
            log_warn "AIUI still running, force killing..."
            kill -9 "$PID" 2>/dev/null
        fi
        rm -f "$AIUI_PID_FILE"
    else
        log_warn "AIUI not running"
        rm -f "$AIUI_PID_FILE" 2>/dev/null
    fi
}

stop_vtn() {
    log_info "Stopping VTN..."
    
    if is_running "$VTN_PID_FILE"; then
        local PID=$(cat "$VTN_PID_FILE")
        kill "$PID" 2>/dev/null && log_success "VTN stopped (PID: $PID)" || log_warn "Failed to stop VTN"
        sleep 1
        
        # Force kill if still running
        if kill -0 "$PID" 2>/dev/null; then
            log_warn "VTN still running, force killing..."
            kill -9 "$PID" 2>/dev/null
        fi
        rm -f "$VTN_PID_FILE"
    else
        log_warn "VTN not running"
        rm -f "$VTN_PID_FILE" 2>/dev/null
    fi
}

stop_playctl() {
    log_info "Stopping PLAYCTL..."
    
    if is_running "$PLAYCTL_PID_FILE"; then
        local PID=$(cat "$PLAYCTL_PID_FILE")
        kill "$PID" 2>/dev/null && log_success "PLAYCTL stopped (PID: $PID)" || log_warn "Failed to stop PLAYCTL"
        sleep 1
        
        # Force kill if still running
        if kill -0 "$PID" 2>/dev/null; then
            log_warn "PLAYCTL still running, force killing..."
            kill -9 "$PID" 2>/dev/null
        fi
        rm -f "$PLAYCTL_PID_FILE"
    else
        log_warn "PLAYCTL not running"
        rm -f "$PLAYCTL_PID_FILE" 2>/dev/null
    fi
}

# ============================================================================
# JACK Routing Functions
# ============================================================================

connect_aiui_vtn_routing() {
    log_info "Configuring AIUI + VTN JACK routing..."
    
    # Wait for required ports
    wait_for_jack_port "vtn:input_1" || return 1
    wait_for_jack_port "vtn:input_2" || return 1
    wait_for_jack_port "vtn:output" || return 1
    wait_for_jack_port "aiui:input" || return 1
    
    # Connect system capture to VTN input
    jack_connect_retry "system:capture_1" "vtn:input_1" || log_warn "Failed to connect capture_1 to vtn"
    jack_connect_retry "system:capture_2" "vtn:input_2" || log_warn "Failed to connect capture_2 to vtn"
    
    # Connect VTN output to AIUI input
    jack_connect_retry "vtn:output" "aiui:input" || return 1
    
    log_success "AIUI + VTN routing configured"
    return 0
}

connect_playctl_routing() {
    log_info "Configuring PLAYCTL JACK routing..."
    
    # Wait for required ports
    wait_for_jack_port "playctl:output_left" || return 1
    wait_for_jack_port "playctl:output_right" || return 1
    
    # Connect playctl outputs to system playback
    jack_connect_retry "playctl:output_left" "system:playback_1" || log_warn "Failed to connect playctl left"
    jack_connect_retry "playctl:output_right" "system:playback_2" || log_warn "Failed to connect playctl right"
    
    log_success "PLAYCTL routing configured"
    return 0
}

connect_vtn_reference_routing() {
    log_info "Configuring VTN reference JACK routing..."
    
    # Wait for required ports
    wait_for_jack_port "playctl:output_left" || return 1
    wait_for_jack_port "playctl:output_right" || return 1
    wait_for_jack_port "vtn:reference_1" || return 1
    wait_for_jack_port "vtn:reference_2" || return 1
    
    # Connect playctl outputs to vtn reference
    jack_connect_retry "playctl:output_left" "vtn:reference_1" || log_warn "Failed to connect vtn:reference_1"
    jack_connect_retry "playctl:output_right" "vtn:reference_2" || log_warn "Failed to connect vtn:reference_1"
    
    log_success "VTN reference routing configured"
    return 0
}

disconnect_all_routing() {
    log_info "Disconnecting all JACK routes..."
    
    # Disconnect AIUI + VTN routes
    jack_disconnect "system:capture_1" "vtn:input_1" 2>/dev/null || true
    jack_disconnect "system:capture_2" "vtn:input_2" 2>/dev/null || true
    jack_disconnect "vtn:output" "aiui:input" 2>/dev/null || true
    
    # Disconnect PLAYCTL routes
    jack_disconnect "playctl:output_left" "system:playback_1" 2>/dev/null || true
    jack_disconnect "playctl:output_right" "system:playback_2" 2>/dev/null || true

    # Disconnect VTN reference routes
    jack_disconnect "playctl:output_left" "vtn:reference_1" 2>/dev/null || true
    jack_disconnect "playctl:output_right" "vtn:reference_2" 2>/dev/null || true
    
    log_success "All routes disconnected"
}

# ============================================================================
# Main Control Functions
# ============================================================================

start() {
    echo "=========================================="
    log_info "Starting all services..."
    echo "=========================================="
    
    # Verify JACK is available
    if ! wait_for_jack; then
        log_error "Cannot proceed without JACK server"
        return 1
    fi
    
    # Start all services
    start_aiui || return 1
    start_vtn || return 1
    start_playctl || return 1
    
    # Wait for services to register with JACK
    log_info "Waiting for services to register with JACK..."
    sleep 3
    
    # Configure routing
    connect_aiui_vtn_routing || log_warn "AIUI+VTN routing failed"
    connect_playctl_routing || log_warn "PLAYCTL routing failed"
    connect_vtn_reference_routing || log_warn "VTN reference routing failed"
    
    echo "=========================================="
    log_success "All services started successfully"
    echo "=========================================="
    
    # Display current JACK connections
    log_info "Current JACK connections:"
    jack_lsp -c 2>/dev/null || log_warn "Could not list JACK connections"
    
    return 0
}

stop() {
    echo "=========================================="
    log_info "Stopping all services..."
    echo "=========================================="
    
    # Disconnect routes first
    disconnect_all_routing
    
    # Stop all services
    stop_playctl
    stop_vtn
    stop_aiui
    
    echo "=========================================="
    log_success "All services stopped"
    echo "=========================================="
}

restart() {
    log_info "Restarting all services..."
    stop
    sleep 2
    start
}

status() {
    echo "=========================================="
    log_info "Service Status"
    echo "=========================================="
    
    # Check AIUI
    if is_running "$AIUI_PID_FILE"; then
        log_success "AIUI is running (PID: $(cat $AIUI_PID_FILE))"
    else
        log_warn "AIUI is not running"
    fi
    
    # Check VTN
    if is_running "$VTN_PID_FILE"; then
        log_success "VTN is running (PID: $(cat $VTN_PID_FILE))"
    else
        log_warn "VTN is not running"
    fi
    
    # Check PLAYCTL
    if is_running "$PLAYCTL_PID_FILE"; then
        log_success "PLAYCTL is running (PID: $(cat $PLAYCTL_PID_FILE))"
    else
        log_warn "PLAYCTL is not running"
    fi
    
    # Check JACK
    if jack_lsp > /dev/null 2>&1; then
        log_success "JACK server is available"
        log_info "JACK connections:"
        jack_lsp -c 2>/dev/null || log_warn "Could not list connections"
    else
        log_error "JACK server is not available"
    fi
    
    echo "=========================================="
}

cleanup() {
    log_warn "Cleanup called, stopping services..."
    stop
    exit 1
}

# ============================================================================
# Signal Handlers
# ============================================================================

# Trap signals for graceful shutdown
trap cleanup SIGTERM SIGINT

# ============================================================================
# Main Execution
# ============================================================================

case "${1:-}" in
    start)
        start
        # Keep script running to prevent container exit
        log_info "Services running. Press Ctrl+C to stop."
        wait
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        log_info "Services restarted. Press Ctrl+C to stop."
        wait
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac