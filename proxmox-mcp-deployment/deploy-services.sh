#!/bin/bash
# MCP Server Platform - Service Deployment Script
# Deploys MCP services to LXC containers with monitoring and service discovery

set -e

# Configuration
CONTAINERS=(201 202 203 204 205 206 207 208 209 210)
BASE_IP="10.0.1"
DOCKER_REGISTRY="localhost:5000"  # Local registry for MCP images
CONSUL_SERVER="${BASE_IP}.201:8500"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Service configurations
declare -A SERVICES=(
    ["201"]="mcp-terminal:terminal-server:8001"
    ["202"]="mcp-puppeteer:puppeteer-server:8002"
    ["203"]="mcp-websearch:websearch-server:8003"
    ["204"]="mcp-filesystem:filesystem-server:8004"
    ["205"]="mcp-automation:automation-server:8005"
    ["206"]="mcp-database:database-server:8006"
    ["207"]="mcp-orchestration:orchestration-server:8007"
    ["208"]="mcp-api-integration:api-integration-server:8008"
    ["209"]="mcp-code-analysis:code-analysis-server:8009"
    ["210"]="mcp-monitoring:monitoring-server:8010"
)

# Check if all containers are running
check_containers() {
    log "Checking container status..."

    for vmid in "${CONTAINERS[@]}"; do
        if ! pct status "$vmid" | grep -q "running"; then
            warn "Container $vmid is not running, starting..."
            pct start "$vmid"
            sleep 5
        fi
    done

    log "All containers are running"
}

# Setup Docker registry on first container
setup_registry() {
    local vmid=201

    log "Setting up Docker registry on container $vmid..."

    pct exec "$vmid" -- bash -c "
        # Install registry
        docker run -d -p 5000:5000 --name registry \
            -v /mcp/data/registry:/var/lib/registry \
            --restart unless-stopped \
            registry:2

        # Wait for registry to start
        sleep 10

        # Test registry
        curl -f http://localhost:5000/v2/ || exit 1
    "

    log "Docker registry setup complete"
}

# Build and push MCP server images
build_and_push_images() {
    log "Building and pushing MCP server images..."

    local build_dir="/tmp/mcp-builds"
    mkdir -p "$build_dir"

    # Create base Dockerfile template
    cat > "$build_dir/Dockerfile.template" << 'EOF'
FROM node:20-alpine

WORKDIR /app

# Install system dependencies
RUN apk add --no-cache curl git bash

# Copy package files
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S mcp && \
    adduser -S mcp -u 1001 -G mcp

# Set ownership
RUN chown -R mcp:mcp /app
USER mcp

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:${MCP_SERVICE_PORT}/health || exit 1

# Expose port
EXPOSE ${MCP_SERVICE_PORT}

# Start command
CMD ["node", "server.js"]
EOF

    # Build images for each service
    for vmid in "${CONTAINERS[@]}"; do
        IFS=':' read -r hostname service port <<< "${SERVICES[$vmid]}"

        info "Building image for $service..."

        # Create service-specific build directory
        local service_dir="$build_dir/$service"
        mkdir -p "$service_dir"

        # Copy service source (would normally be from your repo)
        # For now, create a basic service template
        cat > "$service_dir/package.json" << EOF
{
  "name": "$service",
  "version": "1.0.0",
  "description": "MCP Server - $service",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.0",
    "helmet": "^7.0.0",
    "cors": "^2.8.5",
    "winston": "^3.10.0",
    "consul": "^0.40.0"
  }
}
EOF

        # Create basic server template
        cat > "$service_dir/server.js" << EOF
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const consul = require('consul')();

const app = express();
const PORT = process.env.MCP_SERVICE_PORT || $port;
const SERVICE_NAME = process.env.MCP_SERVICE_NAME || '$service';

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: SERVICE_NAME });
});

// MCP protocol endpoints
app.post('/mcp/call', (req, res) => {
  // MCP call handler
  res.json({ result: 'Method not implemented', service: SERVICE_NAME });
});

// Service registration
const registerService = () => {
  consul.agent.service.register({
    id: SERVICE_NAME,
    name: SERVICE_NAME,
    port: PORT,
    check: {
      http: \`http://localhost:\${PORT}/health\`,
      interval: '10s'
    }
  }, (err) => {
    if (err) {
      console.error('Service registration failed:', err);
    } else {
      console.log(\`Service \${SERVICE_NAME} registered with Consul\`);
    }
  });
};

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(\`\${SERVICE_NAME} running on port \${PORT}\`);

  // Register with Consul after a delay
  setTimeout(registerService, 5000);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('Shutting down gracefully...');
  consul.agent.service.deregister(SERVICE_NAME, () => {
    process.exit(0);
  });
});
EOF

        # Copy Dockerfile
        cp "$build_dir/Dockerfile.template" "$service_dir/Dockerfile"

        # Build and tag image
        docker build -t "$DOCKER_REGISTRY/$service:latest" "$service_dir/"
        docker push "$DOCKER_REGISTRY/$service:latest"

        info "Image built and pushed: $DOCKER_REGISTRY/$service:latest"
    done

    log "All MCP server images built and pushed"
}

# Deploy service to container
deploy_service() {
    local vmid=$1
    local hostname=$2
    local service=$3
    local port=$4
    local ip="${BASE_IP}.${vmid}"

    log "Deploying $service to container $vmid ($ip)..."

    # Create docker-compose file for the service
    pct exec "$vmid" -- bash -c "
        cat > /mcp/docker-compose.yml << 'EOF'
version: '3.8'

networks:
  mcp-local:
    driver: bridge

services:
  $service:
    image: $DOCKER_REGISTRY/$service:latest
    container_name: $service
    hostname: $hostname
    networks:
      - mcp-local
    ports:
      - '$port:$port'
    volumes:
      - /mcp/config:/app/config:ro
      - /mcp/data:/app/data
      - /mcp/logs:/app/logs
    environment:
      - MCP_SERVICE_NAME=$service
      - MCP_SERVICE_PORT=$port
      - CONSUL_AGENT=$CONSUL_SERVER
      - NODE_ENV=production
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: 10m
        max-file: 3
EOF

        # Start the service
        cd /mcp
        docker-compose pull
        docker-compose up -d

        # Wait for service to be ready
        timeout 60 bash -c 'until curl -f http://localhost:$port/health; do sleep 2; done'
    "

    if [[ $? -eq 0 ]]; then
        log "Service $service deployed successfully on container $vmid"
    else
        error "Failed to deploy service $service on container $vmid"
    fi
}

# Setup monitoring stack on designated container
setup_monitoring() {
    local vmid=210  # Monitoring container

    log "Setting up monitoring stack on container $vmid..."

    pct exec "$vmid" -- bash -c "
        # Create monitoring configuration directories
        mkdir -p /mcp/monitoring/{prometheus,grafana,loki}

        # Prometheus configuration
        cat > /mcp/monitoring/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

rule_files:
  - 'rules/*.yml'

scrape_configs:
  - job_name: 'mcp-services'
    consul_sd_configs:
      - server: '$CONSUL_SERVER'
    relabel_configs:
      - source_labels: [__meta_consul_service]
        target_label: service
      - source_labels: [__meta_consul_node]
        target_label: node

  - job_name: 'consul'
    static_configs:
      - targets: ['$CONSUL_SERVER']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['${BASE_IP}.201:9100', '${BASE_IP}.202:9100', '${BASE_IP}.203:9100']
EOF

        # Grafana datasource configuration
        mkdir -p /mcp/monitoring/grafana/datasources
        cat > /mcp/monitoring/grafana/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    access: proxy
    isDefault: true
EOF

        # Deploy monitoring stack
        cat > /mcp/docker-compose.monitoring.yml << 'EOF'
version: '3.8'

networks:
  monitoring:
    driver: bridge

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - '9090:9090'
    volumes:
      - /mcp/monitoring/prometheus:/etc/prometheus
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=30d'
    networks:
      - monitoring
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - '3000:3000'
    volumes:
      - grafana-data:/var/lib/grafana
      - /mcp/monitoring/grafana:/etc/grafana/provisioning
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    networks:
      - monitoring
    restart: unless-stopped

volumes:
  prometheus-data:
  grafana-data:
EOF

        cd /mcp
        docker-compose -f docker-compose.monitoring.yml up -d
    "

    log "Monitoring stack setup complete"
}

# Deploy all services
deploy_all_services() {
    log "Starting deployment of all MCP services..."

    for vmid in "${CONTAINERS[@]}"; do
        IFS=':' read -r hostname service port <<< "${SERVICES[$vmid]}"
        deploy_service "$vmid" "$hostname" "$service" "$port"
    done

    log "All services deployed successfully"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."

    local failed_services=()

    for vmid in "${CONTAINERS[@]}"; do
        IFS=':' read -r hostname service port <<< "${SERVICES[$vmid]}"
        local ip="${BASE_IP}.${vmid}"

        info "Checking $service on $ip:$port..."

        if curl -sf "http://$ip:$port/health" > /dev/null; then
            echo "✅ $service is healthy"
        else
            echo "❌ $service is not responding"
            failed_services+=("$service")
        fi
    done

    if [[ ${#failed_services[@]} -eq 0 ]]; then
        log "All services are healthy!"
    else
        error "Failed services: ${failed_services[*]}"
    fi
}

# Generate service overview
generate_overview() {
    log "Generating service overview..."

    cat > /tmp/mcp-services-overview.txt << 'EOF'
# MCP Server Platform - Service Overview

## Service Endpoints
EOF

    echo "| Service | Container | IP Address | Port | Health Check |" >> /tmp/mcp-services-overview.txt
    echo "|---------|-----------|------------|------|--------------|" >> /tmp/mcp-services-overview.txt

    for vmid in "${CONTAINERS[@]}"; do
        IFS=':' read -r hostname service port <<< "${SERVICES[$vmid]}"
        local ip="${BASE_IP}.${vmid}"
        echo "| $service | $vmid | $ip | $port | http://$ip:$port/health |" >> /tmp/mcp-services-overview.txt
    done

    cat >> /tmp/mcp-services-overview.txt << 'EOF'

## Management URLs
- Consul UI: http://10.0.1.201:8500
- Traefik Dashboard: http://10.0.1.210:8080
- Prometheus: http://10.0.1.210:9090
- Grafana: http://10.0.1.210:3000 (admin/admin123)

## Service Discovery
All services are automatically registered with Consul for service discovery.

## Monitoring
- Prometheus scrapes metrics from all services
- Grafana provides visualization dashboards
- Health checks monitor service availability

## Management Commands
```bash
# Check all service health
for i in {201..210}; do curl -sf http://10.0.1.$i:800$((i-200))/health && echo " ✅ Container $i" || echo " ❌ Container $i"; done

# Restart a service
pct exec 201 -- docker-compose restart

# View service logs
pct exec 201 -- docker-compose logs -f

# Scale a service (on containers that support it)
pct exec 201 -- docker-compose up -d --scale service-name=3
```
EOF

    log "Overview generated: /tmp/mcp-services-overview.txt"
    cat /tmp/mcp-services-overview.txt
}

# Main execution
main() {
    log "Starting MCP service deployment..."

    check_containers
    setup_registry
    build_and_push_images
    deploy_all_services
    setup_monitoring

    # Wait for all services to start
    sleep 30

    verify_deployment
    generate_overview

    log "MCP service deployment completed!"
    log "See /tmp/mcp-services-overview.txt for service details"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi