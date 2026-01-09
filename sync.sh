#!/usr/bin/env bash
set -e
set -u

# -------------------------------------------------------------------
# Destination configuration
# -------------------------------------------------------------------
# Usage:
#   ./sync.sh                     -> remote (default)
#   ./sync.sh cat 172.16.255.127   -> remote
#   ./sync.sh cat local            -> local sync
#   ./sync.sh cat localhost        -> local sync
#   ./sync.sh cat local /tmp/test  -> local sync to custom path
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
# Determine sync mode (local or remote)
# -------------------------------------------------------------------
is_local=false
if [[ "${DEST_HOST}" == "local" || "${DEST_HOST}" == "localhost" ]]; then
    is_local=true
fi

# -------------------------------------------------------------------
# Ensure destination path exists
# -------------------------------------------------------------------
if ${is_local}; then
    echo "Ensuring local destination path exists: ${DEST_PATH}"
    mkdir -p "${DEST_PATH}"
else
    echo "Ensuring remote destination path exists: ${DEST_USER}@${DEST_HOST}:${DEST_PATH}"
    ssh "${DEST_USER}@${DEST_HOST}" "mkdir -p ${DEST_PATH}"
fi

# -------------------------------------------------------------------
# Synchronize files
# -------------------------------------------------------------------
echo "Syncing files..."

if ${is_local}; then
    rsync -avzR --progress "${FILES[@]}" "${DEST_PATH}/"
else
    rsync -avzR --progress "${FILES[@]}" "${DEST_USER}@${DEST_HOST}:${DEST_PATH}/"
fi

echo "All files synced successfully!"
