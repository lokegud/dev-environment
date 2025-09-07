# Agent Terminal System

A comprehensive, production-ready terminal system for agents with personalized environments, real-time logging, and advanced monitoring capabilities.

## Features

### Core Features
- **Personalized Terminal Instances**: Dedicated, isolated containers for each agent
- **Persistent Environments**: Home directories, bash profiles, SSH keys, and workspaces
- **Multi-Session Support**: tmux/screen integration with session management
- **Terminal Recording**: Full session replay with asciinema integration
- **Real-time Logging**: Comprehensive logging with structured data and streaming
- **Web Terminal Interface**: Full-featured web-based terminal with xterm.js

### Advanced Features
- **Log Aggregation**: ELK stack integration for searchable logs
- **Real-time Streaming**: WebSocket-based log streaming and terminal interaction
- **Monitoring & Metrics**: Prometheus and Grafana integration
- **Terminal Sharing**: Collaborative terminal sessions
- **Security**: Container isolation, resource limits, and secure networking
- **Scalability**: Distributed architecture with Redis coordination

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Web Terminal Interface                        │
│                     (React + xterm.js)                          │
├─────────────────────────────────────────────────────────────────┤
│                    Terminal Manager API                          │
│                      (Node.js + Express)                        │
├─────────────────────────────────────────────────────────────────┤
│  Log Streamer  │    Redis         │    Elasticsearch            │
│  (WebSocket)   │  (Coordination)  │    (Log Storage)            │
├─────────────────────────────────────────────────────────────────┤
│              Agent Terminal Containers                           │
│                (Ubuntu + Tools + Logging)                       │
├─────────────────────────────────────────────────────────────────┤
│    Monitoring Stack (Prometheus + Grafana + Kibana)             │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites
- Docker 20.10+
- Docker Compose 2.0+
- 4GB+ RAM available
- 20GB+ disk space

### Installation

1. Clone and setup:
```bash
git clone <repository-url>
cd agent-terminal-system
chmod +x scripts/*.sh
```

2. Run setup:
```bash
./scripts/setup.sh
```

3. Access the system:
- **Web Interface**: http://localhost:8080
- **Terminal Manager API**: http://localhost:3000
- **Kibana (Logs)**: http://localhost:5601
- **Grafana (Metrics)**: http://localhost:3001 (admin/admin)

### First Login
1. Open http://localhost:8080
2. Enter your Agent ID and Name
3. System will create your personalized terminal environment

## Usage

### Terminal Operations

**Create a new terminal:**
```bash
curl -X POST http://localhost:3000/api/terminals \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"agentName": "MyAgent", "theme": "dark"}'
```

**List terminals:**
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/terminals
```

**View logs in real-time:**
```bash
./scripts/view-logs.sh agent-123
```

### Management Commands

**View system status:**
```bash
docker-compose ps
```

**Scale terminals:**
```bash
docker-compose up -d --scale terminal-manager=2
```

**Backup data:**
```bash
docker-compose exec redis redis-cli BGSAVE
docker-compose exec elasticsearch curl -X POST "localhost:9200/_snapshot/backup/snapshot_1"
```

## Configuration

### Environment Variables

Create `.env` file:
```env
# Security
JWT_SECRET=your-secret-key-here
GRAFANA_PASSWORD=admin

# Resource Limits
TERMINAL_MEMORY_LIMIT=512m
TERMINAL_CPU_LIMIT=0.5
MAX_TERMINALS_PER_AGENT=10

# Logging
LOG_LEVEL=info
LOG_RETENTION_DAYS=30

# Features
ENABLE_RECORDING=true
ENABLE_SHARING=true
```

### Terminal Customization

Each agent can customize their terminal through:
- **Profile Scripts**: `~/.bashrc`, `~/.zshrc`
- **Themes**: Multiple built-in themes (dark, matrix, terminal)
- **Aliases & Functions**: Persistent custom commands
- **SSH Keys**: Per-agent SSH key management

### Log Configuration

The system provides multiple log types:
- **Command Logs**: All executed commands with timestamps
- **Session Logs**: Complete terminal session recordings
- **Structured Logs**: JSON formatted events and metadata
- **System Logs**: Container and service logs

## Monitoring

### Grafana Dashboards

Access Grafana at http://localhost:3001:
- **Agent Terminal Overview**: Active terminals, resource usage
- **Log Analytics**: Log volume, error rates, agent activity
- **System Health**: Container status, resource utilization
- **Performance Metrics**: Response times, throughput

### Kibana Logs

Access Kibana at http://localhost:5601:
- **Agent Activity**: Search commands and sessions by agent
- **Error Analysis**: Filter and analyze error logs
- **Usage Patterns**: Visualize agent usage over time
- **Security Monitoring**: Detect suspicious activities

## Security

### Container Security
- Non-root users in containers
- Security profiles and capability dropping
- Read-only filesystems where possible
- Network segmentation

### Data Security
- JWT-based authentication
- TLS encryption for web traffic
- Sensitive data redaction in logs
- Resource limits and quotas

### Access Control
- Agent-based isolation
- Resource quotas per agent
- Audit logging for all actions
- Session recording for compliance

## Development

### Building Images
```bash
# Build all services
docker-compose build

# Build specific service
docker-compose build terminal-manager
```

### Running in Development Mode
```bash
# Start with hot reload
cd services/terminal-manager
npm run dev

# Start web interface with hot reload
cd web-interface
npm start
```

### Testing
```bash
# Run service tests
cd services/terminal-manager
npm test

# Run integration tests
./scripts/test-integration.sh
```

## Troubleshooting

### Common Issues

**Terminals won't start:**
```bash
# Check Docker daemon
docker info

# Check available resources
docker system df

# View service logs
docker-compose logs terminal-manager
```

**Logs not appearing:**
```bash
# Check Elasticsearch status
curl http://localhost:9200/_cluster/health

# Check Logstash pipeline
docker-compose logs logstash
```

**Web interface connection issues:**
```bash
# Check WebSocket connections
docker-compose logs log-streamer

# Verify network connectivity
docker network ls
```

### Log Files

Service logs are available at:
- Terminal Manager: `./logs/terminal-manager.log`
- Log Streamer: `./logs/log-streamer.log`
- Agent Terminals: `./logs/{agent-id}-*.log`

### Performance Tuning

**For high-load environments:**
- Increase Elasticsearch heap size
- Scale terminal-manager service
- Optimize Docker resource limits
- Enable log compression

## Maintenance

### Backup
```bash
# Create full backup
./scripts/backup.sh

# Backup specific components
docker-compose exec redis redis-cli BGSAVE
```

### Cleanup
```bash
# Remove stopped terminals
./scripts/cleanup.sh

# Full cleanup including data
./scripts/cleanup.sh --all
```

### Updates
```bash
# Update services
git pull
docker-compose pull
docker-compose up -d
```

## API Reference

### Authentication
```http
POST /api/auth/login
Content-Type: application/json

{
  "agentId": "agent-123",
  "agentName": "My Agent"
}
```

### Terminal Management
```http
# Create terminal
POST /api/terminals
Authorization: Bearer <token>

# List terminals
GET /api/terminals
Authorization: Bearer <token>

# Get terminal logs
GET /api/terminals/{terminalId}/logs
Authorization: Bearer <token>

# Execute command
POST /api/terminals/{terminalId}/execute
Authorization: Bearer <token>
Content-Type: application/json

{
  "command": "ls -la"
}
```

### WebSocket Events
```javascript
// Connect to terminal
socket.emit('terminal:connect', {
  terminalId: 'terminal-123',
  token: 'jwt-token'
});

// Send input
socket.emit('terminal:input', 'ls -la\n');

// Receive output
socket.on('terminal:output', (data) => {
  console.log(data);
});
```

## License

This project is licensed under the MIT License. See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## Support

For support and questions:
- Check the troubleshooting section
- Review service logs
- Open an issue on GitHub
- Check Grafana dashboards for system health