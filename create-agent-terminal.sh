#!/bin/bash
# Simple Agent Terminal Creation Script

AGENT_ID=${1:-"default-agent"}
COMMAND=${2:-"bash"}

echo "Creating terminal for agent: $AGENT_ID"

# Create agent-specific log directory
LOG_DIR="/tmp/agent-logs/$AGENT_ID"
mkdir -p "$LOG_DIR"

# Run the agent terminal container
CONTAINER_ID=$(docker run -d \
    --name "agent-terminal-$AGENT_ID" \
    -e "AGENT_ID=$AGENT_ID" \
    -v "$LOG_DIR:/tmp/logs" \
    minimal-agent-terminal:latest \
    bash -c "
        echo '=== Agent Terminal Started ==='
        echo 'Agent ID: $AGENT_ID'
        echo 'Timestamp: $(date)'
        echo 'Working Directory: $(pwd)'
        echo 'User: $(whoami)'
        echo
        echo 'Available commands:'
        echo '- python3 --version'
        echo '- curl --version'  
        echo '- tmux --version'
        echo
        echo 'Testing commands:'
        python3 --version
        curl --version 2>&1 | head -1
        tmux -V
        echo
        echo 'Agent $AGENT_ID terminal is ready!'
        echo 'Session log: /tmp/logs/session.log'
        echo '$(date): Agent $AGENT_ID session started' > /tmp/logs/session.log
        
        # Keep container running for demonstration
        tail -f /dev/null
    ")

echo "Container ID: $CONTAINER_ID"
echo "Log directory: $LOG_DIR"

# Show the output
sleep 2
echo "=== Terminal Output ==="
docker logs "agent-terminal-$AGENT_ID"

echo
echo "=== Container Status ==="
docker ps | grep "agent-terminal-$AGENT_ID"

echo
echo "=== Agent Logs ==="
cat "$LOG_DIR/session.log" 2>/dev/null || echo "Session log not created yet"

echo
echo "To view live logs: docker logs -f agent-terminal-$AGENT_ID"
echo "To execute commands: docker exec -it agent-terminal-$AGENT_ID bash"
echo "To stop terminal: docker stop agent-terminal-$AGENT_ID"