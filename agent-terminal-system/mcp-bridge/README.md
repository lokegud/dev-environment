# MCP Terminal Bridge

A production-ready integration bridge that connects AI agents to isolated terminal environments through the MCP (Model Context Protocol) server infrastructure.

## Overview

This bridge provides a seamless way for AI agents to access their own dedicated terminal environments with full logging, monitoring, and security. It leverages the existing proven agent terminal system and exposes it through both REST API and MCP protocol interfaces.

## Features

### Core Functionality
- **Terminal Provisioning**: Create isolated terminal environments for agents on demand
- **Command Execution**: Execute commands in agent terminals with timeout controls  
- **Real-time Logging**: Stream terminal logs with WebSocket support
- **Terminal Management**: Full lifecycle management (create, execute, monitor, destroy)

### Security & Authentication  
- **JWT Authentication**: Token-based authentication for agents
- **Agent Isolation**: Each agent can only access their own terminals
- **Rate Limiting**: Built-in rate limiting and request throttling
- **Security Headers**: Comprehensive security headers and CORS support

### Integration Interfaces
- **REST API**: Complete RESTful API for terminal operations
- **MCP Protocol**: Full MCP server compliance for seamless agent integration
- **WebSocket Streaming**: Real-time terminal output streaming
- **Docker Integration**: Uses proven minimal-agent-terminal Docker images

### Monitoring & Operations
- **Health Checks**: Built-in health monitoring endpoints
- **Audit Logging**: Complete audit trail of all operations
- **Resource Management**: CPU and memory limits for terminals
- **Auto Cleanup**: Automatic cleanup of expired terminals

## Quick Start

### Prerequisites
- Docker and Docker Compose
- Python 3.11+
- Redis (for session management)
- Existing minimal-agent-terminal:latest image

### Installation

1. **Clone and Setup**
   ```bash
   cd /home/loke/agent-terminal-system/mcp-bridge
   cp .env.example .env
   # Edit .env with your configuration
   ```

2. **Start the Bridge**
   
   **Development Mode:**
   ```bash
   ./start-bridge.sh dev
   ```
   
   **Docker Mode:**
   ```bash
   ./start-bridge.sh docker
   ```
   
   **MCP Server Mode:**
   ```bash
   ./start-bridge.sh mcp
   ```

### Testing the Integration

```bash
# Run comprehensive integration tests
python test_integration.py

# Test health
curl http://localhost:8000/health
```

## API Reference

### Authentication
First, get an authentication token:
```bash
curl -X POST http://localhost:8000/auth/token?agent_id=your-agent-id
```

### Terminal Operations

**Create Terminal:**
```bash
curl -X POST http://localhost:8000/terminals \\
  -H "Authorization: Bearer $TOKEN" \\
  -H "Content-Type: application/json" \\
  -d '{
    "agent_id": "your-agent-id",
    "command": "bash",
    "environment": {"KEY": "value"},
    "timeout_hours": 4
  }'
```

**Execute Command:**
```bash
curl -X POST http://localhost:8000/terminals/$TERMINAL_ID/execute \\
  -H "Authorization: Bearer $TOKEN" \\
  -H "Content-Type: application/json" \\
  -d '{
    "command": "ls -la",
    "timeout": 30
  }'
```

**Get Logs:**
```bash
curl http://localhost:8000/terminals/$TERMINAL_ID/logs?lines=100 \\
  -H "Authorization: Bearer $TOKEN"
```

**Stream Logs (WebSocket):**
```javascript
const ws = new WebSocket('ws://localhost:8000/terminals/$TERMINAL_ID/stream?token=$TOKEN');
ws.onmessage = (event) => console.log(event.data);
```

**Destroy Terminal:**
```bash
curl -X DELETE http://localhost:8000/terminals/$TERMINAL_ID \\
  -H "Authorization: Bearer $TOKEN"
```

## MCP Integration

The bridge provides full MCP protocol compliance with these tools:

### Available MCP Tools

1. **create_terminal**
   - Creates a new isolated terminal environment
   - Parameters: agent_id, command, environment, timeout_hours

2. **execute_command** 
   - Executes commands in existing terminals
   - Parameters: terminal_id, command, timeout

3. **get_logs**
   - Retrieves terminal logs
   - Parameters: terminal_id, lines, stream

4. **destroy_terminal**
   - Destroys a terminal and cleans up resources  
   - Parameters: terminal_id

5. **list_terminals**
   - Lists all terminals for the authenticated agent
   - No parameters required

6. **get_terminal_status**
   - Gets detailed status for a specific terminal
   - Parameters: terminal_id

### Using MCP Tools

```python
from mcp_tools import MCPTerminalTools

async with MCPTerminalTools(auth_token=token) as tools:
    # Create terminal
    result = await tools.create_terminal("my-agent")
    terminal_id = result["terminal_id"]
    
    # Execute command  
    result = await tools.execute_command(terminal_id, "python --version")
    print(result["output"])
    
    # Get logs
    result = await tools.get_logs(terminal_id, lines=50)
    print(result["logs"])
    
    # Cleanup
    await tools.destroy_terminal(terminal_id)
```

## Configuration

### Environment Variables

```bash
# Security
JWT_SECRET=your-super-secret-jwt-key
MCP_AUTH_TOKEN=your-mcp-auth-token

# Services  
REDIS_URL=redis://localhost:6379
ELASTICSEARCH_URL=http://localhost:9200

# Terminal Settings
TERMINAL_IMAGE=minimal-agent-terminal:latest
MAX_TERMINALS_PER_AGENT=5
TERMINAL_TIMEOUT_HOURS=4
LOG_BASE_DIR=/tmp/agent-logs
```

### Bridge Configuration
Edit `config/bridge.json` for detailed configuration including:
- Server settings (host, port, workers)
- Security policies (CORS, rate limiting)  
- Terminal resource limits
- Monitoring and logging options

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   AI Agents     │    │  MCP Terminal   │    │ Agent Terminal  │
│                 │◄──►│     Bridge      │◄──►│    System       │
│ (Claude, etc.)  │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                        │                        │
         │              ┌─────────▼─────────┐              │
         │              │                   │              │
         │              │  Infrastructure   │              │
         └──────────────┤                   │◄─────────────┘
           MCP Protocol │ • Redis           │ Docker Containers
                        │ • Elasticsearch   │
                        │ • Nginx           │
                        │ • Monitoring      │
                        └───────────────────┘
```

## Deployment

### Docker Compose (Recommended)
```bash
# Production deployment
./start-bridge.sh docker

# View logs
docker-compose logs -f terminal-bridge
```

### Kubernetes (Optional)
K8s manifests available in `k8s/` directory for production deployments.

### Manual Deployment
```bash
# Install dependencies
python3 -m venv venv
source venv/bin/activate  
pip install -r requirements.txt

# Start services
redis-server
python server.py
```

## Monitoring

### Health Checks
- **Endpoint**: `GET /health`
- **Response**: Service health, active terminals, dependency status

### Logs
- **Application Logs**: `/app/logs/bridge.log`
- **Terminal Logs**: `/tmp/agent-logs/$AGENT_ID/$TERMINAL_ID/`
- **Docker Logs**: `docker-compose logs`

### Metrics (Optional)
- Prometheus metrics on port 9090 (if enabled)
- Grafana dashboards for visualization

## Security Considerations

1. **JWT Tokens**: Use strong, unique JWT secrets
2. **Network Security**: Run behind reverse proxy (Nginx included)
3. **Resource Limits**: CPU and memory limits enforced per terminal
4. **Container Isolation**: Each terminal runs in isolated Docker container
5. **Audit Logging**: All operations logged for security auditing

## Troubleshooting

### Common Issues

**Bridge server won't start:**
```bash
# Check Docker connectivity
docker info

# Check Redis connectivity  
redis-cli ping

# Check logs
tail -f logs/bridge.log
```

**Terminal creation fails:**
```bash
# Verify terminal image exists
docker image inspect minimal-agent-terminal:latest

# Check Docker permissions
docker ps
```

**Authentication issues:**
```bash
# Verify JWT configuration
echo $JWT_SECRET

# Test token creation
curl -X POST http://localhost:8000/auth/token?agent_id=test
```

### Support
For issues and support:
1. Check logs: `docker-compose logs -f`
2. Run integration tests: `python test_integration.py`
3. Verify configuration: `cat .env`

## License

MIT License - see LICENSE file for details.