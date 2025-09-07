#!/bin/bash

# MCP Server Platform Deployment Script
set -e

# Configuration
DEPLOYMENT_TYPE=${1:-docker}  # docker or k3s
ENVIRONMENT=${2:-development}  # development, staging, production
NAMESPACE="mcp-platform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [ "$DEPLOYMENT_TYPE" == "docker" ]; then
        if ! command -v docker &> /dev/null; then
            log_error "Docker is not installed"
            exit 1
        fi
        if ! command -v docker-compose &> /dev/null; then
            log_error "Docker Compose is not installed"
            exit 1
        fi
    elif [ "$DEPLOYMENT_TYPE" == "k3s" ]; then
        if ! command -v kubectl &> /dev/null; then
            log_error "kubectl is not installed"
            exit 1
        fi
    fi
    
    log_info "Prerequisites check passed"
}

setup_environment() {
    log_info "Setting up environment variables..."
    
    if [ ! -f ".env" ]; then
        log_warn ".env file not found, creating from template..."
        cat > .env << EOF
# MCP Server Platform Environment Variables
NODE_ENV=${ENVIRONMENT}
MCP_AUTH_TOKEN=$(openssl rand -hex 32)
REDIS_PASSWORD=$(openssl rand -hex 16)
DB_PASSWORD=$(openssl rand -hex 16)
SEARCH_API_KEY=your-search-api-key
VAULT_ADDR=http://vault:8200
VAULT_TOKEN=$(openssl rand -hex 32)
EOF
        log_info ".env file created with random passwords"
    fi
    
    source .env
}

deploy_docker() {
    log_info "Deploying with Docker Compose..."
    
    cd docker
    
    # Build images
    log_info "Building Docker images..."
    docker-compose build
    
    # Start services
    log_info "Starting services..."
    docker-compose up -d
    
    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    sleep 10
    
    # Check status
    docker-compose ps
    
    log_info "Docker deployment complete!"
    log_info "Access the services at:"
    echo "  - Terminal: http://localhost:8001"
    echo "  - Puppeteer: http://localhost:8002"
    echo "  - WebSearch: http://localhost:8003"
    echo "  - FileSystem: http://localhost:8004"
    echo "  - Automation: http://localhost:8005"
    echo "  - Traefik Dashboard: http://localhost:8080"
}

deploy_k3s() {
    log_info "Deploying to K3s cluster..."
    
    # Create namespace
    log_info "Creating namespace..."
    kubectl apply -f k3s/namespace.yaml
    
    # Create secrets from .env
    log_info "Creating secrets..."
    kubectl create secret generic mcp-server-secrets \
        --from-literal=auth-token="${MCP_AUTH_TOKEN}" \
        --from-literal=redis-password="${REDIS_PASSWORD}" \
        --from-literal=db-password="${DB_PASSWORD}" \
        --namespace=${NAMESPACE} \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply configurations
    log_info "Applying configurations..."
    kubectl apply -f k3s/configmap.yaml
    kubectl apply -f k3s/rbac.yaml
    
    # Deploy supporting services
    log_info "Deploying supporting services..."
    kubectl apply -f k3s/supporting-services.yaml
    
    # Wait for supporting services
    log_info "Waiting for supporting services to be ready..."
    kubectl wait --for=condition=ready pod -l app=redis -n ${NAMESPACE} --timeout=60s
    kubectl wait --for=condition=ready pod -l app=postgres -n ${NAMESPACE} --timeout=60s
    
    # Deploy MCP servers
    log_info "Deploying MCP servers..."
    kubectl apply -f k3s/deployments.yaml
    kubectl apply -f k3s/services.yaml
    kubectl apply -f k3s/ingress.yaml
    
    # Wait for deployments
    log_info "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available deployment --all -n ${NAMESPACE} --timeout=300s
    
    # Check status
    kubectl get pods -n ${NAMESPACE}
    kubectl get services -n ${NAMESPACE}
    kubectl get ingress -n ${NAMESPACE}
    
    log_info "K3s deployment complete!"
}

cleanup_docker() {
    log_info "Cleaning up Docker deployment..."
    cd docker
    docker-compose down -v
    log_info "Docker cleanup complete"
}

cleanup_k3s() {
    log_info "Cleaning up K3s deployment..."
    kubectl delete namespace ${NAMESPACE}
    log_info "K3s cleanup complete"
}

show_usage() {
    echo "Usage: $0 [docker|k3s] [development|staging|production] [deploy|cleanup]"
    echo ""
    echo "Examples:"
    echo "  $0 docker development deploy    # Deploy to Docker in development mode"
    echo "  $0 k3s production deploy        # Deploy to K3s in production mode"
    echo "  $0 docker development cleanup   # Clean up Docker deployment"
}

# Main execution
main() {
    ACTION=${3:-deploy}
    
    if [ "$ACTION" == "help" ] || [ "$ACTION" == "--help" ]; then
        show_usage
        exit 0
    fi
    
    log_info "Starting MCP Server Platform deployment"
    log_info "Type: $DEPLOYMENT_TYPE, Environment: $ENVIRONMENT, Action: $ACTION"
    
    check_prerequisites
    setup_environment
    
    if [ "$ACTION" == "deploy" ]; then
        if [ "$DEPLOYMENT_TYPE" == "docker" ]; then
            deploy_docker
        elif [ "$DEPLOYMENT_TYPE" == "k3s" ]; then
            deploy_k3s
        else
            log_error "Invalid deployment type: $DEPLOYMENT_TYPE"
            show_usage
            exit 1
        fi
    elif [ "$ACTION" == "cleanup" ]; then
        if [ "$DEPLOYMENT_TYPE" == "docker" ]; then
            cleanup_docker
        elif [ "$DEPLOYMENT_TYPE" == "k3s" ]; then
            cleanup_k3s
        else
            log_error "Invalid deployment type: $DEPLOYMENT_TYPE"
            show_usage
            exit 1
        fi
    else
        log_error "Invalid action: $ACTION"
        show_usage
        exit 1
    fi
    
    log_info "Operation completed successfully!"
}

# Run main function
main