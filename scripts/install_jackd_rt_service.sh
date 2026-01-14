#!/bin/bash
# install_jackd_rt_system.sh
# Install / update JACK Audio Server as a realtime SYSTEM service
# Safe to run multiple times (idempotent)

set -e

# -------------------------------------------------------------------
# Root check
# -------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run this script as root"
  exit 1
fi

# -------------------------------------------------------------------
# Config (can be overridden via env)
# -------------------------------------------------------------------
JACK_DEVICE="${JACK_DEVICE:-hw:0}"
JACK_RATE="${JACK_RATE:-16000}"
JACK_PERIOD="${JACK_PERIOD:-640}"
JACK_NPERIODS="${JACK_NPERIODS:-2}"
JACK_PRIORITY="${JACK_PRIORITY:-80}"

SYSCTL_FILE="/etc/sysctl.d/99-jack-rt.conf"
SERVICE_FILE="/etc/systemd/system/jackd.service"

# -------------------------------------------------------------------
# Sanity check
# -------------------------------------------------------------------
if ! command -v jackd >/dev/null 2>&1; then
  echo "❌ jackd is not installed"
  exit 1
fi

echo "▶ Installing / updating JACK realtime system service"

# -------------------------------------------------------------------
# 0. Stop existing jackd service if running
# -------------------------------------------------------------------
if systemctl list-unit-files | grep -q '^jackd.service'; then
  if systemctl is-active --quiet jackd.service; then
    echo "▶ Stopping running jackd.service..."
    systemctl stop jackd.service
  else
    echo "ℹ jackd.service exists but is not running"
  fi
else
  echo "ℹ jackd.service not found (fresh install)"
fi

# -------------------------------------------------------------------
# 1. Kernel realtime sysctl (PERMANENT)
# -------------------------------------------------------------------
echo "▶ Configuring kernel realtime scheduling..."

cat > "$SYSCTL_FILE" <<EOF
# Allow unlimited realtime runtime (required by JACK)
kernel.sched_rt_runtime_us = -1
kernel.sched_rt_period_us = 1000000
EOF

sysctl --system >/dev/null

# -------------------------------------------------------------------
# 2. Write systemd service
# -------------------------------------------------------------------
echo "▶ Writing systemd service..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=JACK Audio Server (Realtime)
After=sound.target
Requires=sound.target

[Service]
Type=simple

# Realtime limits
LimitRTPRIO=95
LimitMEMLOCK=infinity
LimitNICE=-20

# systemd scheduling
CPUSchedulingPolicy=rr
CPUSchedulingPriority=${JACK_PRIORITY}
IOSchedulingClass=realtime
Nice=-10

# JACK runtime
Environment=JACK_NO_AUDIO_RESERVATION=1

ExecStart=/usr/bin/jackd -R -n system -P ${JACK_PRIORITY} -d alsa -d ${JACK_DEVICE} -r ${JACK_RATE} -p ${JACK_PERIOD} -n ${JACK_NPERIODS}

Restart=on-failure
RestartSec=2
NoNewPrivileges=no

[Install]
WantedBy=multi-user.target
EOF

# -------------------------------------------------------------------
# 3. Reload systemd & start service
# -------------------------------------------------------------------
echo "▶ Reloading systemd and starting service..."

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable jackd.service >/dev/null
systemctl start jackd.service

# -------------------------------------------------------------------
# 4. Status
# -------------------------------------------------------------------
echo
echo "✅ JACK realtime system service installed / updated"
systemctl status jackd.service --no-pager
