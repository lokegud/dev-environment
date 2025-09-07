#!/bin/bash
# Agent Terminal System Cleanup Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo -e "${BLUE}=== Agent Terminal System Cleanup ===${NC}"

# Function to stop and remove all agent terminals
cleanup_terminals() {
    print_status "Stopping and removing all agent terminal containers..."
    
    # Get all agent terminal containers
    CONTAINERS=$(docker ps -aq --filter label=agent.id)
    
    if [ -n "$CONTAINERS" ]; then
        echo "Found agent terminal containers:"
        docker ps --filter label=agent.id --format "table {{.Names}}\t{{.Labels}}\t{{.Status}}"
        
        # Stop containers
        print_status "Stopping containers..."
        docker stop $CONTAINERS 2>/dev/null || true
        
        # Remove containers
        print_status "Removing containers..."
        docker rm $CONTAINERS 2>/dev/null || true
    else
        print_status "No agent terminal containers found."
    fi
}

# Function to stop main services
stop_services() {
    print_status "Stopping main services..."
    docker-compose down
}

# Function to remove volumes
remove_volumes() {
    if [ "$1" = "--volumes" ]; then
        print_warning "Removing all data volumes..."
        echo "This will delete all stored data including logs, databases, and configurations."
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker-compose down -v
            docker volume rm $(docker volume ls -q --filter label=com.docker.compose.project=agent-terminal-system) 2>/dev/null || true
            print_status "Volumes removed."
        else
            print_status "Volume removal cancelled."
        fi
    fi
}

# Function to remove images
remove_images() {
    if [ "$1" = "--images" ]; then
        print_warning "Removing Docker images..."
        
        # Remove agent terminal images
        docker rmi agent-terminal:latest 2>/dev/null || true
        
        # Remove built service images
        docker rmi $(docker images --filter label=com.docker.compose.project=agent-terminal-system -q) 2>/dev/null || true
        
        print_status "Images removed."
    fi
}

# Function to clean up networks
cleanup_networks() {
    print_status "Cleaning up networks..."
    docker network rm agent-terminal-net 2>/dev/null || true
}

# Function to clean up log files
cleanup_logs() {
    if [ "$1" = "--logs" ]; then
        print_warning "Removing log files..."
        read -p "This will delete all log files. Continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf ./logs/*
            print_status "Log files removed."
        else
            print_status "Log file removal cancelled."
        fi
    fi
}

# Function to show cleanup status
show_status() {
    echo
    print_status "Cleanup Status:"
    echo "Containers: $(docker ps -q --filter label=agent.id | wc -l) agent terminals still running"
    echo "Volumes: $(docker volume ls -q --filter label=com.docker.compose.project=agent-terminal-system | wc -l) volumes remaining"
    echo "Images: $(docker images -q agent-terminal 2>/dev/null | wc -l) agent terminal images remaining"
    echo "Log files: $(find ./logs -type f 2>/dev/null | wc -l) log files remaining"
}

# Main cleanup function
main() {
    local REMOVE_VOLUMES=false
    local REMOVE_IMAGES=false
    local REMOVE_LOGS=false
    local FORCE=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --volumes)
                REMOVE_VOLUMES=true
                shift
                ;;
            --images)
                REMOVE_IMAGES=true
                shift
                ;;
            --logs)
                REMOVE_LOGS=true
                shift
                ;;
            --all)
                REMOVE_VOLUMES=true
                REMOVE_IMAGES=true
                REMOVE_LOGS=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --volumes    Remove data volumes (databases, configs)"
                echo "  --images     Remove Docker images"
                echo "  --logs       Remove log files"
                echo "  --all        Remove everything"
                echo "  --force      Skip confirmation prompts"
                echo "  -h, --help   Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information."
                exit 1
                ;;
        esac
    done
    
    if [ "$FORCE" = false ]; then
        echo "This will stop and remove Agent Terminal System components."
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Cleanup cancelled."
            exit 0
        fi
    fi
    
    cleanup_terminals
    stop_services
    
    if [ "$REMOVE_VOLUMES" = true ]; then
        remove_volumes --volumes
    fi
    
    if [ "$REMOVE_IMAGES" = true ]; then
        remove_images --images
    fi
    
    if [ "$REMOVE_LOGS" = true ]; then
        cleanup_logs --logs
    fi
    
    cleanup_networks
    
    # Clean up orphaned containers and networks
    print_status "Cleaning up Docker system..."
    docker system prune -f >/dev/null 2>&1 || true
    
    show_status
    
    echo
    print_status "Cleanup completed!"
    
    if [ "$REMOVE_VOLUMES" = false ]; then
        echo
        print_warning "Data volumes were preserved. Use --volumes to remove them."
    fi
    
    if [ "$REMOVE_IMAGES" = false ]; then
        echo
        print_warning "Docker images were preserved. Use --images to remove them."
    fi
}

# Run main function with all arguments
main "$@"