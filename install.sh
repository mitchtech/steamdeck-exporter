#!/bin/sh

# Configuration
NODE_EXPORTER_VERSION="1.8.0"
NODE_EXPORTER_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
NODE_EXPORTER_CHECKSUM_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/sha256sums.txt"
TARGET_DIR="/home/deck/node_exporter"
SERVICE_FILE="/home/deck/steamdeck-node-exporter.service"
SYSTEMD_USER_DIR="/home/deck/.config/systemd/user"
LOG_FILE="/home/deck/node_exporter_setup.log"
MAX_RETRIES=3
REQUIRED_SPACE_MB=50

# Define function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Handle script interruptions
cleanup() {
    log "Script interrupted. Cleaning up..."
    rm -rf "$TEMP_DIR"
    exit 1
}

trap cleanup INT TERM

# Check if wget is installed
if ! command -v wget > /dev/null 2>&1; then
    log "Error: wget is not installed. Please install wget and try again."
    exit 1
fi

# Check if systemd service file exists
if [ ! -f "$SERVICE_FILE" ]; then
    log "Error: Systemd service file $SERVICE_FILE not found."
    exit 1
fi

# Check for sufficient disk space
AVAILABLE_SPACE=$(df /home | tail -1 | awk '{print $4}')
AVAILABLE_SPACE_MB=$((AVAILABLE_SPACE / 1024))
if [ "$AVAILABLE_SPACE_MB" -lt "$REQUIRED_SPACE_MB" ]; then
    log "Error: Not enough disk space. At least ${REQUIRED_SPACE_MB}MB required."
    exit 1
fi

# Check if the script is running on Linux
if [ "$(uname -s)" != "Linux" ]; then
    log "Error: Detected host OS not Linux. This script intended for use directly on Steamdeck."
    exit 1
fi

# Check if the architecture is amd64
if [ "$(uname -m)" != "x86_64" ]; then
    log "Error: Detected architecture not x86_64 (amd64). This script intended for use directly on Steamdeck."
    exit 1
fi

# Check if systemd is present
if ! pidof systemd > /dev/null; then
    log "Error: systemd is not running. This script intended for use directly on Steamdeck."
    exit 1
fi

log "Starting Prometheus Node Exporter setup on SteamDeck."

# Create a temporary directory for the download
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

# Retry logic for downloading node_exporter
download_node_exporter() {
    for i in $(seq 1 "$MAX_RETRIES"); do
        log "Downloading node_exporter (attempt $i)..."
        wget "$NODE_EXPORTER_URL"
        wget "$NODE_EXPORTER_CHECKSUM_URL"
        if [ $? -eq 0 ]; then
            log "Download successful."
            return 0
        fi
        log "Download failed. Retrying..."
        sleep 1
    done
    log "Download failed after $MAX_RETRIES attempts."
    rm -rf "$TEMP_DIR"
    exit 1
}

download_node_exporter

# Verify download integrity
log "Verifying download integrity..."
grep "$(sha256sum node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz | awk '{print $1}')" sha256sums.txt
if [ $? -eq 0 ]; then
    log "Download integrity verified."
else
    log "Download integrity verification failed."
    rm -rf "$TEMP_DIR"
    exit 1
fi

log "Extracting node_exporter..."
tar xvf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

if [ $? -eq 0 ]; then
    log "Extraction successful."
else
    log "Extraction failed."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Backup existing installation if present
if [ -d "$TARGET_DIR" ]; then
    log "Backing up existing node_exporter installation..."
    mv "$TARGET_DIR" "${TARGET_DIR}_backup_$(date +'%Y%m%d%H%M%S')"
    if [ $? -eq 0 ]; then
        log "Backup successful."
    else
        log "Backup failed."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

log "Moving node_exporter to target directory..."
mkdir -p "$TARGET_DIR"
mv "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/"* "$TARGET_DIR"

if [ $? -eq 0 ]; then
    log "Move successful."
    rm "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
else
    log "Move failed."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Clean up temporary directory
rm -rf "$TEMP_DIR"

# Check if the user is deck
if [ "$USER" != "deck" ]; then
    log "Warning: This script should be run as the 'deck' user."
fi

# Ensure the systemd user directory exists
mkdir -p "$SYSTEMD_USER_DIR"

# Copy systemd service config file
log "Copying systemd service config file..."
cp "$SERVICE_FILE" "$SYSTEMD_USER_DIR"

if [ $? -eq 0 ]; then
    log "Copy successful."
else
    log "Copy failed."
    exit 1
fi

# Enable and start the service
log "Enabling systemd service..."
systemctl --user enable steamdeck-node-exporter.service

if [ $? -eq 0 ]; then
    log "Service enabled successfully."
else
    log "Service enabling failed."
    exit 1
fi

# Check if the service is already running
log "Checking if the service is already running..."
systemctl --user is-active --quiet steamdeck-node-exporter.service

if [ $? -eq 0 ]; then
    log "Service is already running."
else
    log "Starting systemd service..."
    systemctl --user start steamdeck-node-exporter.service

    if [ $? -eq 0 ]; then
        log "Service started successfully."
    else
        log "Service start failed."
        exit 1
    fi
fi

log "Setup completed. Metrics endpoint active at http://localhost:9100/metrics"

# Instructions for managing the service
echo "
To check the status of the service:
systemctl --user status steamdeck-node-exporter.service

To stop the service:
systemctl --user stop steamdeck-node-exporter.service

To disable the service from starting on boot:
systemctl --user disable steamdeck-node-exporter.service
" | tee -a "$LOG_FILE"
