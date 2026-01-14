#!/usr/bin/env bash

set -e
set -u

# ============================================================================ 
# Configuration
# ============================================================================ 

AIUI_DIR="."
VTN_DIR="."
PLAYCTL_DIR="."

AIUI_BIN="asrd"
VTN_BIN="znoise"
PLAYCTL_BIN="playctl"

AIUI_PID_FILE="/tmp/asrd.pid"
VTN_PID_FILE="/tmp/znoise.pid"
PLAYCTL_PID_FILE="/tmp/playctl.pid"

MAX_WAIT_ATTEMPTS=30
WAIT_INTERVAL=2
MAX_CONNECT_RETRIES=5

# ============================================================================ 
# Colors
# ============================================================================ 

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================ 
# Helpers
# ============================================================================ 

is_running() {
    if [ -f "$1" ]; then
        PID=$(cat "$1")
        if kill -0 "$PID" 2>/dev/null; then return 0; fi
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
    local source=$1 dest=$2 attempt=0
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
# Start Services
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
    ./$AIUI_BIN 2>&1 &
    echo $! > $AIUI_PID_FILE
    log_success "AIUI started (PID: $(cat $AIUI_PID_FILE))"
    sleep 2
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
    ./$VTN_BIN 2>&1 &
    echo $! > $VTN_PID_FILE
    log_success "VTN started (PID: $(cat $VTN_PID_FILE))"
    sleep 2
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
    ./$PLAYCTL_BIN 2>&1 &
    echo $! > $PLAYCTL_PID_FILE
    log_success "PLAYCTL started (PID: $(cat $PLAYCTL_PID_FILE))"
    sleep 2
}

# ============================================================================ 
# Stop Services
# ============================================================================ 

stop_aiui() {
    log_info "Stopping AIUI..."
    if is_running "$AIUI_PID_FILE"; then
        PID=$(cat "$AIUI_PID_FILE")
        kill "$PID" 2>/dev/null && log_success "AIUI stopped (PID: $PID)" || log_warn "Failed to stop AIUI"
        sleep 1
        kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
        rm -f "$AIUI_PID_FILE"
    else
        log_warn "AIUI not running"
    fi
}

stop_vtn() {
    log_info "Stopping VTN..."
    if is_running "$VTN_PID_FILE"; then
        PID=$(cat "$VTN_PID_FILE")
        kill "$PID" 2>/dev/null && log_success "VTN stopped (PID: $PID)" || log_warn "Failed to stop VTN"
        sleep 1
        kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
        rm -f "$VTN_PID_FILE"
    else
        log_warn "VTN not running"
    fi
}

stop_playctl() {
    log_info "Stopping PLAYCTL..."
    if is_running "$PLAYCTL_PID_FILE"; then
        PID=$(cat "$PLAYCTL_PID_FILE")
        kill "$PID" 2>/dev/null && log_success "PLAYCTL stopped (PID: $PID)" || log_warn "Failed to stop PLAYCTL"
        sleep 1
        kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
        rm -f "$PLAYCTL_PID_FILE"
    else
        log_warn "PLAYCTL not running"
    fi
}

# ============================================================================ 
# JACK Routing
# ============================================================================ 

connect_aiui_vtn_routing() {
    wait_for_jack_port "vtn:input_1" || return 1
    wait_for_jack_port "vtn:input_2" || return 1
    wait_for_jack_port "vtn:output" || return 1
    wait_for_jack_port "aiui:input" || return 1
    jack_connect_retry "system:capture_1" "vtn:input_1" || log_warn "Failed"
    jack_connect_retry "system:capture_2" "vtn:input_2" || log_warn "Failed"
    jack_connect_retry "vtn:output" "aiui:input" || return 1
}

connect_playctl_routing() {
    wait_for_jack_port "playctl:output_left" || return 1
    wait_for_jack_port "playctl:output_right" || return 1
    jack_connect_retry "playctl:output_left" "system:playback_1" || log_warn "Failed"
    jack_connect_retry "playctl:output_right" "system:playback_2" || log_warn "Failed"
}

connect_vtn_reference_routing() {
    wait_for_jack_port "playctl:output_left" || return 1
    wait_for_jack_port "playctl:output_right" || return 1
    wait_for_jack_port "vtn:reference_1" || return 1
    wait_for_jack_port "vtn:reference_2" || return 1
    jack_connect_retry "playctl:output_left" "vtn:reference_1" || log_warn "Failed"
    jack_connect_retry "playctl:output_right" "vtn:reference_2" || log_warn "Failed"
}

disconnect_all_routing() {
    jack_disconnect "system:capture_1" "vtn:input_1" 2>/dev/null || true
    jack_disconnect "system:capture_2" "vtn:input_2" 2>/dev/null || true
    jack_disconnect "vtn:output" "aiui:input" 2>/dev/null || true
    jack_disconnect "playctl:output_left" "system:playback_1" 2>/dev/null || true
    jack_disconnect "playctl:output_right" "system:playback_2" 2>/dev/null || true
    jack_disconnect "playctl:output_left" "vtn:reference_1" 2>/dev/null || true
    jack_disconnect "playctl:output_right" "vtn:reference_2" 2>/dev/null || true
}

# ============================================================================ 
# Main
# ============================================================================ 

start() {
    log_info "Starting all services..."
    wait_for_jack || { log_error "JACK unavailable"; return 1; }
    start_aiui
    start_vtn
    start_playctl
    sleep 3
    connect_aiui_vtn_routing || log_warn "AIUI+VTN routing failed"
    connect_playctl_routing || log_warn "PLAYCTL routing failed"
    connect_vtn_reference_routing || log_warn "VTN reference routing failed"
    log_success "All services started"
}

stop() {
    log_info "Stopping all services..."
    disconnect_all_routing
    stop_playctl
    stop_vtn
    stop_aiui
    log_success "All services stopped"
}

restart() { stop; sleep 2; start; }

status() {
    [ -f "$AIUI_PID_FILE" ] && log_success "AIUI running" || log_warn "AIUI not running"
    [ -f "$VTN_PID_FILE" ] && log_success "VTN running" || log_warn "VTN not running"
    [ -f "$PLAYCTL_PID_FILE" ] && log_success "PLAYCTL running" || log_warn "PLAYCTL not running"
    jack_lsp > /dev/null 2>&1 && log_success "JACK server available" || log_error "JACK unavailable"
}

cleanup() { log_warn "Stopping services..."; stop; exit 1; }

trap cleanup SIGTERM SIGINT

case "${1:-}" in
    start) start; log_info "Services running"; wait ;;
    stop) stop ;;
    restart) restart; log_info "Services restarted"; wait ;;
    status) status ;;
    *) echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
