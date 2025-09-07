# Agent Terminal System - Recovery Instructions

## Quick Recovery (if system is down)

### 1. Check Docker Status
```bash
sudo systemctl status docker
sudo systemctl start docker  # if not running
```

### 2. Check Existing Containers
```bash
docker ps -a | grep agent-terminal
```

### 3. Start the MCP Bridge API
```bash
cd /home/loke/agent-terminal-system/mcp-bridge
source venv/bin/activate
python simple_bridge.py
```

### 4. Verify System Health
```bash
curl http://localhost:8000/health
curl http://localhost:8000/terminals
```

## Full System Rebuild (if containers lost)

### 1. Rebuild Docker Image
```bash
cd /home/loke/agent-terminal-system/docker
docker build -f Dockerfile.minimal-terminal -t minimal-agent-terminal:latest .
```

### 2. Start Core Services
```bash
cd /home/loke/agent-terminal-system
docker-compose up -d redis elasticsearch
```

### 3. Start MCP Bridge
```bash
cd mcp-bridge
source venv/bin/activate
python simple_bridge.py
```

## Create New Agent Terminal
```bash
curl -X POST "http://localhost:8000/terminals/create?agent_id=YOUR_AGENT_NAME"
```

## Backup Files Created
- `/home/loke/AGENT_TERMINAL_SYSTEM_BACKUP.md` - Complete documentation
- `/home/loke/agent-terminal-system-backup-*.tar.gz` - System files archive
- `/home/loke/SYSTEM_STATUS_*.txt` - Current system status
- `/home/loke/RECOVERY_INSTRUCTIONS.md` - This file

## Important Paths
- **Main System**: `/home/loke/agent-terminal-system/`
- **API Server**: `/home/loke/agent-terminal-system/mcp-bridge/simple_bridge.py`
- **Creation Script**: `/home/loke/create-agent-terminal.sh`
- **Docker Image**: `minimal-agent-terminal:latest`

## Default Ports
- **8000**: MCP Bridge API
- **6379**: Redis
- **9200**: Elasticsearch

## Contact/Support
All configuration and code is preserved in the backup files above.