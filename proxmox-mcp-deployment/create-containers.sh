#!/bin/bash
# MCP Server Platform - Proxmox LXC Container Creation Script
# Creates 10 LXC containers for comprehensive MCP server deployment

set -e

# Configuration
TEMPLATE="/var/lib/vz/template/cache/debian-12-standard_12.0-1_amd64.tar.zst"
BRIDGE="vmbr1"
GATEWAY="10.0.1.1"
STORAGE_POOL="local-zfs"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Container configurations: vmid:hostname:cores:memory:storage:ip
declare -A CONTAINERS=(
    ["201"]="mcp-terminal:1:1024:8:10.0.1.201"
    ["202"]="mcp-puppeteer:4:4096:20:10.0.1.202"
    ["203"]="mcp-websearch:2:2048:12:10.0.1.203"
    ["204"]="mcp-filesystem:1:1024:16:10.0.1.204"
    ["205"]="mcp-automation:2:2048:12:10.0.1.205"
    ["206"]="mcp-database:4:6144:32:10.0.1.206"
    ["207"]="mcp-orchestration:4:4096:24:10.0.1.207"
    ["208"]="mcp-api:2:2048:12:10.0.1.208"
    ["209"]="mcp-code-analysis:3:4096:20:10.0.1.209"
    ["210"]="mcp-monitoring:3:4096:32:10.0.1.210"
)

# Pre-flight checks
check_prerequisites() {
    log "Performing pre-flight checks..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi

    # Check if template exists
    if [[ ! -f "$TEMPLATE" ]]; then
        error "Container template not found: $TEMPLATE"
    fi

    # Check if bridge exists
    if ! ip link show "$BRIDGE" &>/dev/null; then
        error "Network bridge $BRIDGE not found"
    fi

    # Check storage pool
    if ! zfs list "$STORAGE_POOL" &>/dev/null; then
        error "ZFS storage pool $STORAGE_POOL not found"
    fi

    log "Pre-flight checks passed"
}

# Create ZFS datasets for shared storage
create_zfs_datasets() {
    log "Creating ZFS datasets..."

    local datasets=(
        "mcp-data"
        "mcp-backup"
        "mcp-logs"
    )

    for dataset in "${datasets[@]}"; do
        if ! zfs list "${STORAGE_POOL}/${dataset}" &>/dev/null; then
            log "Creating dataset: ${STORAGE_POOL}/${dataset}"
            zfs create "${STORAGE_POOL}/${dataset}"
            zfs set compression=lz4 "${STORAGE_POOL}/${dataset}"
            zfs set atime=off "${STORAGE_POOL}/${dataset}"
        else
            log "Dataset already exists: ${STORAGE_POOL}/${dataset}"
        fi
    done
}

# Create individual container
create_container() {
    local vmid=$1
    local hostname=$2
    local cores=$3
    local memory=$4
    local storage=$5
    local ip=$6

    log "Creating container $vmid ($hostname)..."

    # Check if container already exists
    if pct list | grep -q "^$vmid "; then
        warn "Container $vmid already exists, skipping..."
        return 0
    fi

    # Create container
    pct create "$vmid" "$TEMPLATE" \
        --hostname "$hostname" \
        --cores "$cores" \
        --memory "$memory" \
        --swap 512 \
        --rootfs "${STORAGE_POOL}:${storage}" \
        --net0 "name=eth0,bridge=${BRIDGE},ip=${ip}/24,gw=${GATEWAY}" \
        --unprivileged 1 \
        --features "nesting=0,keyctl=0" \
        --mp0 "${STORAGE_POOL}/mcp-data:subvol-${vmid}-config,mp=/mcp/config" \
        --mp1 "${STORAGE_POOL}/mcp-data:subvol-${vmid}-data,mp=/mcp/data" \
        --mp2 "${STORAGE_POOL}/mcp-logs:subvol-shared,mp=/mcp/logs" \
        --mp3 "${STORAGE_POOL}/mcp-backup:subvol-${vmid}-backup,mp=/mcp/backup" \
        --start 0 \
        --onboot 1 \
        --protection 0

    if [[ $? -eq 0 ]]; then
        log "Container $vmid ($hostname) created successfully"

        # Configure container post-creation
        configure_container "$vmid" "$hostname"
    else
        error "Failed to create container $vmid"
    fi
}

# Configure container after creation
configure_container() {
    local vmid=$1
    local hostname=$2

    log "Configuring container $vmid..."

    # Start container for configuration
    pct start "$vmid"
    sleep 10

    # Basic package installation and configuration
    pct exec "$vmid" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y curl wget git htop nano net-tools dnsutils
        apt-get install -y docker.io docker-compose-plugin
        systemctl enable docker

        # Create MCP user
        useradd -m -s /bin/bash mcp
        usermod -aG docker mcp

        # Create directory structure
        mkdir -p /mcp/{config,data,logs,backup}
        chown -R mcp:mcp /mcp

        # Install Node.js
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs

        # Create systemd service template
        cat > /etc/systemd/system/mcp-server.service << 'EOF'
[Unit]
Description=MCP Server for $hostname
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=mcp
WorkingDirectory=/mcp
ExecStart=/usr/bin/node /mcp/server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
    "

    # Stop container after configuration
    pct stop "$vmid"

    log "Container $vmid configured successfully"
}

# Main deployment function
deploy_containers() {
    log "Starting MCP container deployment..."

    local total=${#CONTAINERS[@]}
    local current=0

    for vmid in $(printf '%s\n' "${!CONTAINERS[@]}" | sort -n); do
        current=$((current + 1))
        IFS=':' read -r hostname cores memory storage ip <<< "${CONTAINERS[$vmid]}"

        log "[$current/$total] Processing container $vmid..."
        create_container "$vmid" "$hostname" "$cores" "$memory" "$storage" "$ip"
    done
}

# Generate container summary
generate_summary() {
    log "Generating deployment summary..."

    cat > /tmp/mcp-containers-summary.txt << 'EOF'
# MCP Server Platform - Container Summary

## Container Allocation
EOF

    echo "| VMID | Hostname | Cores | Memory | Storage | IP Address |" >> /tmp/mcp-containers-summary.txt
    echo "|------|----------|--------|---------|---------|------------|" >> /tmp/mcp-containers-summary.txt

    for vmid in $(printf '%s\n' "${!CONTAINERS[@]}" | sort -n); do
        IFS=':' read -r hostname cores memory storage ip <<< "${CONTAINERS[$vmid]}"
        echo "| $vmid | $hostname | ${cores} | ${memory}MB | ${storage}GB | $ip |" >> /tmp/mcp-containers-summary.txt
    done

    cat >> /tmp/mcp-containers-summary.txt << 'EOF'

## Resource Totals
- Total CPU Cores: 26
- Total Memory: 30GB
- Total Storage: 198GB
- Network Range: 10.0.1.201-210/24

## Next Steps
1. Start containers: `for i in {201..210}; do pct start $i; done`
2. Deploy MCP services to each container
3. Configure service discovery and load balancing
4. Set up monitoring and backup automation

## Management Commands
```bash
# List all MCP containers
pct list | grep mcp-

# Start all containers
for i in {201..210}; do pct start $i; done

# Stop all containers
for i in {201..210}; do pct stop $i; done

# Container health check
for i in {201..210}; do echo "=== Container $i ==="; pct status $i; done
```
EOF

    log "Summary generated: /tmp/mcp-containers-summary.txt"
    cat /tmp/mcp-containers-summary.txt
}

# Main execution
main() {
    log "MCP Server Platform Deployment Starting..."

    check_prerequisites
    create_zfs_datasets
    deploy_containers
    generate_summary

    log "MCP container deployment completed successfully!"
    log "See /tmp/mcp-containers-summary.txt for details"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi