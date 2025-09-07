#!/bin/bash
# Agent Terminal System Setup Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="agent-terminal-system"
DOCKER_NETWORK="agent-terminal-net"
LOG_DIR="./logs"
DATA_DIR="./data"

echo -e "${BLUE}=== Agent Terminal System Setup ===${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose (V2)
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    print_status "Prerequisites check passed!"
}

# Create necessary directories
create_directories() {
    print_status "Creating directories..."
    
    mkdir -p "${LOG_DIR}"/{elasticsearch,logstash,grafana}
    mkdir -p "${DATA_DIR}"/{elasticsearch,redis,prometheus,grafana}
    mkdir -p ./config/{grafana-dashboards,prometheus-rules}
    mkdir -p ./ssl
    
    # Set proper permissions
    chmod -R 755 "${LOG_DIR}"
    chmod -R 755 "${DATA_DIR}"
    
    print_status "Directories created successfully!"
}

# Generate SSL certificates (self-signed for development)
generate_ssl() {
    print_status "Generating SSL certificates..."
    
    if [ ! -f ./ssl/server.crt ]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout ./ssl/server.key \
            -out ./ssl/server.crt \
            -subj "/C=US/ST=State/L=City/O=AgentTerminal/OU=Dev/CN=localhost"
        
        print_status "SSL certificates generated!"
    else
        print_status "SSL certificates already exist."
    fi
}

# Create environment file
create_env_file() {
    print_status "Creating environment file..."
    
    if [ ! -f .env ]; then
        cat > .env << EOF
# Agent Terminal System Environment Configuration

# Security
JWT_SECRET=$(openssl rand -hex 32)
GRAFANA_PASSWORD=admin

# Service URLs
ELASTICSEARCH_URL=http://elasticsearch:9200
REDIS_URL=redis://redis:6379
PROMETHEUS_URL=http://prometheus:9090

# Log Configuration
LOG_LEVEL=info
ENABLE_DEBUG=false

# Terminal Configuration
DEFAULT_THEME=dark
MAX_TERMINALS_PER_AGENT=10
TERMINAL_MEMORY_LIMIT=512m
TERMINAL_CPU_LIMIT=0.5

# Network Configuration
NETWORK_NAME=${DOCKER_NETWORK}

# Data Retention
LOG_RETENTION_DAYS=30
METRICS_RETENTION_DAYS=15

# Feature Flags
ENABLE_RECORDING=true
ENABLE_SHARING=true
ENABLE_COLLABORATION=false
EOF
        print_status "Environment file created!"
    else
        print_status "Environment file already exists."
    fi
}

# Build Docker images
build_images() {
    print_status "Building Docker images..."
    
    # Build agent terminal image
    print_status "Building agent terminal base image..."
    docker build -t agent-terminal:latest -f docker/Dockerfile.agent-terminal docker/
    
    # Build service images using docker compose
    print_status "Building service images..."
    docker compose build
    
    print_status "Docker images built successfully!"
}

# Initialize Elasticsearch indices
init_elasticsearch() {
    print_status "Waiting for Elasticsearch to be ready..."
    
    # Wait for Elasticsearch to be healthy
    timeout=300
    count=0
    while ! curl -s http://localhost:9200/_cluster/health | grep -q '"status":"green\|yellow"'; do
        sleep 5
        count=$((count + 5))
        if [ $count -ge $timeout ]; then
            print_error "Elasticsearch failed to start within timeout"
            return 1
        fi
        echo -n "."
    done
    echo
    
    print_status "Creating Elasticsearch index templates..."
    
    # Create index template for logs
    curl -X PUT "localhost:9200/_index_template/agent-terminal-logs" \
        -H 'Content-Type: application/json' \
        -d '{
            "index_patterns": ["agent-terminal-logs-*"],
            "template": {
                "settings": {
                    "number_of_shards": 1,
                    "number_of_replicas": 0,
                    "index.refresh_interval": "5s"
                },
                "mappings": {
                    "properties": {
                        "@timestamp": { "type": "date" },
                        "agent_id": { "type": "keyword" },
                        "agent_name": { "type": "text" },
                        "session_id": { "type": "keyword" },
                        "event_type": { "type": "keyword" },
                        "log_type": { "type": "keyword" },
                        "message": { "type": "text" },
                        "command": { "type": "text" },
                        "source_file": { "type": "keyword" },
                        "data": { "type": "object" }
                    }
                }
            }
        }'
    
    # Create index template for events
    curl -X PUT "localhost:9200/_index_template/agent-terminal-events" \
        -H 'Content-Type: application/json' \
        -d '{
            "index_patterns": ["agent-terminal-events-*"],
            "template": {
                "settings": {
                    "number_of_shards": 1,
                    "number_of_replicas": 0
                },
                "mappings": {
                    "properties": {
                        "timestamp": { "type": "date" },
                        "agent_id": { "type": "keyword" },
                        "event_type": { "type": "keyword" },
                        "data": { "type": "object" }
                    }
                }
            }
        }'
    
    print_status "Elasticsearch indices initialized!"
}

# Setup Grafana dashboards
setup_grafana() {
    print_status "Setting up Grafana dashboards..."
    
    # Create dashboard directory
    mkdir -p ./config/grafana-dashboards
    
    # Create a sample dashboard
    cat > ./config/grafana-dashboards/agent-terminal-overview.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Agent Terminal Overview",
    "tags": ["agent-terminal"],
    "style": "dark",
    "timezone": "browser",
    "panels": [
      {
        "title": "Active Terminals",
        "type": "stat",
        "targets": [
          {
            "expr": "count(container_last_seen{name=~\"agent-terminal-.*\"})",
            "legendFormat": "Active Terminals"
          }
        ],
        "gridPos": {"h": 8, "w": 6, "x": 0, "y": 0}
      },
      {
        "title": "Terminal CPU Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total{name=~\"agent-terminal-.*\"}[5m]) * 100",
            "legendFormat": "{{name}}"
          }
        ],
        "gridPos": {"h": 8, "w": 18, "x": 6, "y": 0}
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "10s"
  }
}
EOF

    print_status "Grafana dashboards configured!"
}

# Create management scripts
create_scripts() {
    print_status "Creating management scripts..."
    
    # Terminal management script
    cat > scripts/manage-terminals.sh << 'EOF'
#!/bin/bash
# Terminal management script

ACTION=$1
AGENT_ID=$2

case $ACTION in
    "list")
        echo "Active terminals:"
        docker ps --filter label=agent.id --format "table {{.Names}}\t{{.Labels}}\t{{.Status}}"
        ;;
    "create")
        if [ -z "$AGENT_ID" ]; then
            echo "Usage: $0 create <agent-id>"
            exit 1
        fi
        echo "Creating terminal for agent: $AGENT_ID"
        curl -X POST http://localhost:3000/api/terminals \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer YOUR_TOKEN" \
            -d "{\"agentId\":\"$AGENT_ID\"}"
        ;;
    "destroy")
        if [ -z "$AGENT_ID" ]; then
            echo "Usage: $0 destroy <terminal-id>"
            exit 1
        fi
        echo "Destroying terminal: $AGENT_ID"
        curl -X DELETE http://localhost:3000/api/terminals/$AGENT_ID \
            -H "Authorization: Bearer YOUR_TOKEN"
        ;;
    *)
        echo "Usage: $0 {list|create|destroy} [agent-id|terminal-id]"
        exit 1
        ;;
esac
EOF
    
    # Log viewer script
    cat > scripts/view-logs.sh << 'EOF'
#!/bin/bash
# Log viewer script

AGENT_ID=$1
LOG_TYPE=${2:-"all"}

if [ -z "$AGENT_ID" ]; then
    echo "Usage: $0 <agent-id> [plaintext|structured|recording|all]"
    exit 1
fi

case $LOG_TYPE in
    "plaintext")
        tail -f logs/${AGENT_ID}-*.log
        ;;
    "structured")
        tail -f logs/${AGENT_ID}-structured.jsonl | jq '.'
        ;;
    "recording")
        ls logs/${AGENT_ID}-recording-*.cast
        echo "Use 'asciinema play <file>' to replay"
        ;;
    "all")
        tail -f logs/${AGENT_ID}-*
        ;;
esac
EOF
    
    chmod +x scripts/*.sh
    print_status "Management scripts created!"
}

# Main setup function
main() {
    print_status "Starting Agent Terminal System setup..."
    
    check_prerequisites
    create_directories
    generate_ssl
    create_env_file
    
    print_status "Starting services..."
    docker compose up -d elasticsearch redis
    
    sleep 10
    init_elasticsearch
    
    build_images
    
    print_status "Starting remaining services..."
    docker compose up -d
    
    setup_grafana
    create_scripts
    
    print_status "Waiting for all services to be ready..."
    sleep 30
    
    echo
    echo -e "${GREEN}=== Setup Complete! ===${NC}"
    echo
    echo "Services available at:"
    echo -e "  ${BLUE}Web Interface:${NC}     http://localhost:8080"
    echo -e "  ${BLUE}Terminal Manager:${NC}  http://localhost:3000"
    echo -e "  ${BLUE}Log Streaming:${NC}    http://localhost:8081"
    echo -e "  ${BLUE}Kibana:${NC}           http://localhost:5601"
    echo -e "  ${BLUE}Grafana:${NC}          http://localhost:3001 (admin/admin)"
    echo -e "  ${BLUE}Prometheus:${NC}       http://localhost:9090"
    echo
    echo "Management commands:"
    echo -e "  ${BLUE}View logs:${NC}        ./scripts/view-logs.sh <agent-id>"
    echo -e "  ${BLUE}Manage terminals:${NC} ./scripts/manage-terminals.sh list"
    echo -e "  ${BLUE}Stop system:${NC}      docker compose down"
    echo -e "  ${BLUE}Clean system:${NC}     docker compose down -v"
    echo
}

# Run main function
main "$@"