# MCP Server Platform

A comprehensive Model Context Protocol (MCP) server platform providing modular capabilities for AI agents.

## Architecture Overview

The platform consists of 5 core MCP servers:

1. **Terminal Server** - Shell and terminal access
2. **Puppeteer Server** - Browser automation
3. **WebSearch Server** - Web searching and scraping
4. **FileSystem Server** - File system operations
5. **Automation Server** - Workflow automation and integrations

## Quick Start

### Prerequisites

- Docker and Docker Compose (for containerized deployment)
- Kubernetes/K3s cluster (for orchestrated deployment)
- Node.js 20+ (for development)

### Docker Deployment

```bash
# Clone the repository
git clone https://github.com/your-org/mcp-server-platform.git
cd mcp-server-platform

# Set environment variables
cp .env.example .env
# Edit .env with your configuration

# Build and start all services
cd docker
docker-compose up -d

# Check service status
docker-compose ps
```

### K3s Deployment

```bash
# Apply K3s configurations
kubectl apply -f k3s/namespace.yaml
kubectl apply -f k3s/configmap.yaml
kubectl apply -f k3s/rbac.yaml
kubectl apply -f k3s/deployments.yaml
kubectl apply -f k3s/services.yaml
kubectl apply -f k3s/ingress.yaml

# Check deployment status
kubectl get pods -n mcp-platform
kubectl get services -n mcp-platform
```

## Agent Configuration

Agents can select up to 3 MCP servers based on their requirements. Each agent configuration specifies:

- Server endpoints and authentication
- Capabilities needed from each server
- Resource limits
- Task/workflow definitions

### Example Agent Types

1. **Web Developer Agent**
   - Terminal Server (for running commands)
   - Puppeteer Server (for browser testing)
   - FileSystem Server (for code management)

2. **Data Analyst Agent**
   - WebSearch Server (for data collection)
   - FileSystem Server (for data storage)
   - Automation Server (for scheduled pipelines)

3. **DevOps Agent**
   - Terminal Server (for infrastructure commands)
   - Automation Server (for CI/CD workflows)
   - FileSystem Server (for configuration management)

## Server Capabilities

### Terminal Server (Port 8001)
- Shell access (bash, sh, zsh)
- Command execution
- PTY support
- Session management

### Puppeteer Server (Port 8002)
- Headless browser automation
- Screenshot and PDF generation
- Web testing
- Form interaction

### WebSearch Server (Port 8003)
- Multi-engine search (Google, Bing, DuckDuckGo)
- Web scraping
- Content extraction
- Result caching

### FileSystem Server (Port 8004)
- File CRUD operations
- Directory management
- File watching
- Archive operations

### Automation Server (Port 8005)
- Cron scheduling
- Workflow orchestration
- Notifications (email, Slack, webhooks)
- API integrations

## Security Features

- Token-based authentication
- TLS encryption for all communications
- Network policies and segmentation
- Rate limiting
- Audit logging
- Sandboxed execution environments
- RBAC for Kubernetes deployments

## Networking

### Docker Network
- Bridge network: 172.20.0.0/16
- Inter-service communication via container names
- Traefik gateway for routing

### K3s Network
- ClusterIP services for internal communication
- Ingress controller for external access
- Network policies for security
- Service mesh ready

## Monitoring and Observability

- Health checks for all services
- Prometheus metrics endpoints
- Centralized logging
- Distributed tracing support

## Development

### Running Locally

```bash
# Install dependencies
npm install

# Start individual server
node servers/terminal-server/index.js

# Run tests
npm test
```

### Building Custom Servers

1. Extend the base MCP server class
2. Implement required capabilities
3. Add server configuration
4. Create Docker image
5. Deploy to platform

## API Documentation

Each server exposes APIs following the MCP specification:

- WebSocket endpoints for real-time communication
- HTTP/gRPC endpoints for request-response
- Standardized error handling
- Rate limiting and throttling

## Troubleshooting

### Common Issues

1. **Connection refused**
   - Check service status
   - Verify network policies
   - Check authentication tokens

2. **Resource limits**
   - Adjust CPU/memory limits
   - Scale replicas
   - Check storage availability

3. **Authentication failures**
   - Verify token configuration
   - Check secret mounting
   - Review RBAC permissions

## Contributing

Please see CONTRIBUTING.md for guidelines.

## License

MIT License - see LICENSE file for details.