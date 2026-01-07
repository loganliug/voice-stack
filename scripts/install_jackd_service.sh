#!/bin/bash
# install_jackd_service.sh
# Install and enable user-level JACK Audio Server systemd service
# Supports configurable JACK device and default server via environment variables

set -e

SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/jackd.service"

# Default environment variables (can be overridden before running the script)
: "${JACK_DEVICE:=plughw:0,0}"          # default audio device
: "${JACK_DEFAULT_SERVER:=default}"     # default JACK server

# Check if jackd is installed
if ! command -v jackd &> /dev/null; then
    echo "Error: jackd is not installed. Please install it first."
    exit 1
fi

# Create systemd user directory if it does not exist
mkdir -p "$SERVICE_DIR"

# Stop existing service if running
if systemctl --user is-active --quiet jackd.service; then
    echo "Stopping existing jackd.service..."
    systemctl --user stop jackd.service
fi

# Write the service file using tee
tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=JACK Audio Server
After=sound.target

[Service]
Type=simple
Environment=JACK_NO_AUDIO_RESERVATION=1
Environment=JACK_DEVICE=$JACK_DEVICE
Environment=JACK_DEFAULT_SERVER=$JACK_DEFAULT_SERVER
ExecStart=/usr/bin/jackd -d alsa -d \${JACK_DEVICE} -r 16000 -p 640 -n 2
Restart=on-failure

[Install]
WantedBy=default.target
EOF

# Reload systemd user configuration
systemctl --user daemon-reload

# Enable and start the service
systemctl --user enable --now jackd.service

# Show the status of the service
echo "JACK Audio Server has been installed and started. Current status:"
systemctl --user status jackd.service --no-pager
