#!/bin/bash
# Simple Agent Terminal System Setup Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Simple Agent Terminal System Setup ===${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
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

# Create directories
create_directories() {
    print_status "Creating directories..."
    mkdir -p ./logs
    mkdir -p ./data/redis
    chmod -R 755 ./logs ./data
    print_status "Directories created!"
}

# Build and start
build_and_start() {
    print_status "Building agent terminal base image..."
    docker build -t agent-terminal:latest -f docker/Dockerfile.agent-terminal docker/
    
    print_status "Starting simple terminal system..."
    docker compose -f docker-compose.simple.yml up -d --build
    
    print_status "Waiting for services to be ready..."
    sleep 15
}

# Test the system
test_system() {
    print_status "Testing system endpoints..."
    
    # Wait for services
    timeout=60
    count=0
    while ! curl -s http://localhost:3000/health > /dev/null; do
        sleep 2
        count=$((count + 2))
        if [ $count -ge $timeout ]; then
            print_error "Terminal manager failed to start"
            return 1
        fi
        echo -n "."
    done
    echo
    
    print_status "System is ready!"
}

# Create a quick test terminal
create_test_terminal() {
    print_status "Creating test terminal for agent 'test-agent'..."
    
    # Create test terminal
    TERMINAL_ID=$(curl -s -X POST http://localhost:3000/api/terminals \
        -H "Content-Type: application/json" \
        -d '{"agentId":"test-agent","agentName":"Test Agent"}' | \
        grep -o '"terminalId":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$TERMINAL_ID" ]; then
        print_status "Test terminal created with ID: $TERMINAL_ID"
        echo -e "${YELLOW}You can connect to it at: http://localhost:8080?terminal=$TERMINAL_ID${NC}"
    else
        print_error "Failed to create test terminal"
    fi
}

# Main setup function
main() {
    print_status "Starting simple agent terminal system setup..."
    
    check_prerequisites
    create_directories
    build_and_start
    test_system
    create_test_terminal
    
    echo
    echo -e "${GREEN}=== Simple Setup Complete! ===${NC}"
    echo
    echo "Services available at:"
    echo -e "  ${BLUE}Web Interface:${NC}     http://localhost:8080"
    echo -e "  ${BLUE}Terminal Manager:${NC}  http://localhost:3000"
    echo -e "  ${BLUE}Log Streaming:${NC}    http://localhost:8081"
    echo
    echo "To view terminal logs:"
    echo -e "  ${BLUE}Basic logs:${NC}       docker compose -f docker-compose.simple.yml logs -f"
    echo -e "  ${BLUE}Agent logs:${NC}       tail -f logs/test-agent-*.log"
    echo
    echo "To stop the system:"
    echo -e "  ${BLUE}Stop:${NC}             docker compose -f docker-compose.simple.yml down"
    echo
}

# Run main function
main "$@"