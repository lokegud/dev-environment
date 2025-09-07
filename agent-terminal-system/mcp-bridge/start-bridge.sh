#!/bin/bash
# MCP Terminal Bridge Startup Script

set -e

# Configuration
BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="$BRIDGE_DIR/logs"
CONFIG_DIR="$BRIDGE_DIR/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== MCP Terminal Bridge Startup ===${NC}"
echo "Bridge directory: $BRIDGE_DIR"

# Create necessary directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p "$LOGS_DIR" "$CONFIG_DIR"

# Check if .env exists, create from example if not
if [ ! -f "$BRIDGE_DIR/.env" ]; then
    echo -e "${YELLOW}Creating .env from example...${NC}"
    cp "$BRIDGE_DIR/.env.example" "$BRIDGE_DIR/.env"
    echo -e "${YELLOW}Please edit .env file with your configuration${NC}"
fi

# Source environment variables
if [ -f "$BRIDGE_DIR/.env" ]; then
    echo -e "${YELLOW}Loading environment variables...${NC}"
    export $(grep -v '^#' "$BRIDGE_DIR/.env" | xargs)
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running or not accessible${NC}"
    exit 1
fi

# Check if minimal-agent-terminal image exists
if ! docker image inspect minimal-agent-terminal:latest > /dev/null 2>&1; then
    echo -e "${YELLOW}Warning: minimal-agent-terminal:latest image not found${NC}"
    echo -e "${YELLOW}You may need to build the terminal image first${NC}"
fi

# Function to check service health
check_service_health() {
    local service_name=$1
    local url=$2
    local max_attempts=30
    local attempt=1
    
    echo -e "${YELLOW}Checking $service_name health...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "$url" > /dev/null 2>&1; then
            echo -e "${GREEN}$service_name is healthy${NC}"
            return 0
        fi
        
        echo -n "."
        sleep 2
        ((attempt++))
    done
    
    echo -e "${RED}$service_name health check failed${NC}"
    return 1
}

# Start services based on mode
MODE=${1:-"dev"}

case $MODE in
    "dev")
        echo -e "${BLUE}Starting in development mode...${NC}"
        
        # Install dependencies if needed
        if [ ! -d "venv" ]; then
            echo -e "${YELLOW}Creating virtual environment...${NC}"
            python3 -m venv venv
            source venv/bin/activate
            pip install -r requirements.txt
        else
            source venv/bin/activate
        fi
        
        # Start Redis if not running
        if ! redis-cli ping > /dev/null 2>&1; then
            echo -e "${YELLOW}Starting Redis...${NC}"
            redis-server --daemonize yes
            sleep 2
        fi
        
        # Start the bridge server
        echo -e "${GREEN}Starting MCP Terminal Bridge...${NC}"
        python server.py
        ;;
        
    "docker")
        echo -e "${BLUE}Starting with Docker Compose...${NC}"
        
        # Build and start services
        docker-compose up --build -d
        
        # Check health of services
        echo -e "${YELLOW}Waiting for services to start...${NC}"
        sleep 10
        
        check_service_health "Redis" "redis://localhost:6379" || true
        check_service_health "Terminal Bridge" "http://localhost:8000/health"
        
        echo -e "${GREEN}Services are running!${NC}"
        echo -e "${BLUE}Terminal Bridge: http://localhost:8000${NC}"
        echo -e "${BLUE}Logs: docker-compose logs -f${NC}"
        ;;
        
    "mcp")
        echo -e "${BLUE}Starting MCP server mode...${NC}"
        
        # Setup environment for MCP server
        if [ ! -d "venv" ]; then
            echo -e "${YELLOW}Creating virtual environment...${NC}"
            python3 -m venv venv
            source venv/bin/activate
            pip install -r requirements.txt
        else
            source venv/bin/activate
        fi
        
        # Start MCP server
        echo -e "${GREEN}Starting MCP Terminal Server...${NC}"
        python mcp_server.py
        ;;
        
    "stop")
        echo -e "${BLUE}Stopping services...${NC}"
        docker-compose down
        pkill -f "python server.py" || true
        pkill -f "python mcp_server.py" || true
        redis-cli shutdown || true
        echo -e "${GREEN}Services stopped${NC}"
        ;;
        
    *)
        echo -e "${RED}Unknown mode: $MODE${NC}"
        echo "Usage: $0 [dev|docker|mcp|stop]"
        echo ""
        echo "Modes:"
        echo "  dev    - Development mode (local Python)"
        echo "  docker - Docker Compose mode"
        echo "  mcp    - MCP server mode"
        echo "  stop   - Stop all services"
        exit 1
        ;;
esac

echo -e "${GREEN}MCP Terminal Bridge startup complete!${NC}"