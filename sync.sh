#!/usr/bin/env bash
set -e
set -u

# -------------------------------------------------------------------
# Default target host information
# -------------------------------------------------------------------
DEST_USER=${1:-cat}
DEST_HOST=${2:-172.16.255.127}
DEST_PATH=${3:-/home/cat/workspace/voice-stack-release}

# -------------------------------------------------------------------
# List of files and directories to sync
# -------------------------------------------------------------------
FILES=(
    "res/"
    "crates/vtn/vtn-sys/vendor/linaro7.5.0_x64_release/"
    "Dockerfile"
    "compose.yaml"
    "voice-stack-deployment.yaml"
    ".env"
    "run.sh"
    "scripts/"
    "target/aarch64-unknown-linux-gnu/release/znoise"
    "target/aarch64-unknown-linux-gnu/release/asrd"
    "target/aarch64-unknown-linux-gnu/release/playctl"
)

# -------------------------------------------------------------------
# Ensure destination path exists on remote host
# -------------------------------------------------------------------
echo "Ensuring destination path exists on ${DEST_HOST}"
ssh "${DEST_USER}@${DEST_HOST}" "mkdir -p ${DEST_PATH}"

# -------------------------------------------------------------------
# Synchronize files using rsync
# -------------------------------------------------------------------
echo "Syncing files to ${DEST_USER}@${DEST_HOST}:${DEST_PATH}"

# Use -a (archive), -v (verbose), -z (compress), -R (relative) to preserve paths
rsync -avzR --progress "${FILES[@]}" "${DEST_USER}@${DEST_HOST}:${DEST_PATH}/"

echo "All files synced!"
