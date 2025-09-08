#!/bin/bash
set -e

echo "🚀 Setting up development environment..."

# Update system packages
sudo apt-get update

# Install additional tools
sudo apt-get install -y \
    tmux \
    vim \
    htop \
    jq \
    curl \
    wget \
    build-essential \
    software-properties-common

# Setup Docker compose if not present
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Install Python dependencies if requirements files exist
if [ -f "/workspace/agent-terminal-system/mcp-bridge/requirements.txt" ]; then
    echo "Installing Python dependencies for MCP Bridge..."
    pip install -r /workspace/agent-terminal-system/mcp-bridge/requirements.txt
fi

# Install Node dependencies for services
for service_dir in /workspace/agent-terminal-system/services/*/; do
    if [ -f "${service_dir}package.json" ]; then
        echo "Installing Node dependencies for $(basename $service_dir)..."
        cd "$service_dir" && npm install
    fi
done

# Setup environment variables
cat >> ~/.bashrc << 'EOL'

# Development Environment Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias dc='docker-compose'
alias k='kubectl'

# Project shortcuts
alias agent-term='cd /workspace/agent-terminal-system'
alias mcp-server='cd /workspace/mcp-server-platform'

# Docker shortcuts
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dil='docker image ls'
alias dcup='docker-compose up -d'
alias dcdown='docker-compose down'
alias dclogs='docker-compose logs -f'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

EOL

# Create workspace directories if they don't exist
mkdir -p /workspace/logs
mkdir -p /workspace/data
mkdir -p /workspace/temp

# Set proper permissions
sudo chown -R vscode:vscode /workspace

echo "✅ Development environment setup complete!"
echo ""
echo "📁 Project Structure:"
echo "  - Agent Terminal System: /workspace/agent-terminal-system"
echo "  - MCP Server Platform: /workspace/mcp-server-platform"
echo ""
echo "🔧 Available Commands:"
echo "  - agent-term: Navigate to Agent Terminal System"
echo "  - mcp-server: Navigate to MCP Server Platform"
echo "  - dc: Docker Compose shortcut"
echo "  - k: Kubectl shortcut"
echo ""
echo "📚 Next Steps:"
echo "  1. Run 'agent-term' to navigate to the Agent Terminal System"
echo "  2. Run 'docker-compose up -d' to start services"
echo "  3. Check logs with 'docker-compose logs -f'"