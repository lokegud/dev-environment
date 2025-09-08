terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.12.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.0"
    }
  }
}

variable "docker_arch" {
  description = "Architecture for Docker images"
  default     = "amd64"
  validation {
    condition     = contains(["amd64", "arm64"], var.docker_arch)
    error_message = "Docker architecture must be amd64 or arm64"
  }
}

data "coder_parameter" "cpu_cores" {
  name         = "cpu_cores"
  display_name = "CPU Cores"
  description  = "Number of CPU cores for the workspace"
  default      = "4"
  type         = "number"
  icon         = "/emojis/1f5a5.png"
  mutable      = true
  validation {
    min = 1
    max = 16
  }
}

data "coder_parameter" "memory_gb" {
  name         = "memory_gb"
  display_name = "Memory (GB)"
  description  = "Amount of memory in GB for the workspace"
  default      = "8"
  type         = "number"
  icon         = "/emojis/1f9e0.png"
  mutable      = true
  validation {
    min = 1
    max = 32
  }
}

data "coder_parameter" "disk_size_gb" {
  name         = "disk_size_gb"
  display_name = "Disk Size (GB)"
  description  = "Size of the persistent volume in GB"
  default      = "50"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false
  validation {
    min = 10
    max = 500
  }
}

data "coder_parameter" "enable_docker" {
  name         = "enable_docker"
  display_name = "Enable Docker in Docker"
  description  = "Enable Docker inside the workspace (requires more resources)"
  default      = "true"
  type         = "bool"
  icon         = "/emojis/1f433.png"
  mutable      = true
}

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git Repository URL"
  description  = "Git repository to clone (optional)"
  default      = "https://github.com/lokegud/dev-environment"
  type         = "string"
  icon         = "/emojis/1f4c1.png"
  mutable      = false
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}

provider "docker" {}

resource "coder_agent" "main" {
  os   = "linux"
  arch = var.docker_arch
  
  startup_script = <<-EOT
    set -e
    
    # Install additional tools
    sudo apt-get update && sudo apt-get install -y \
      tmux vim htop jq curl wget build-essential
    
    # Clone repository if specified
    if [ -n "${data.coder_parameter.git_repo.value}" ]; then
      if [ ! -d "/home/coder/workspace" ]; then
        git clone ${data.coder_parameter.git_repo.value} /home/coder/workspace
      fi
    fi
    
    # Setup environment
    echo 'export WORKSPACE_FOLDER=/home/coder/workspace' >> ~/.bashrc
    echo 'export AGENT_TERMINAL_PATH=/home/coder/workspace/agent-terminal-system' >> ~/.bashrc
    echo 'export MCP_SERVER_PATH=/home/coder/workspace/mcp-server-platform' >> ~/.bashrc
    
    # Add aliases
    cat >> ~/.bashrc << 'EOF'
    alias ll='ls -alF'
    alias la='ls -A'
    alias dc='docker-compose'
    alias k='kubectl'
    alias agent-term='cd $AGENT_TERMINAL_PATH'
    alias mcp-server='cd $MCP_SERVER_PATH'
    alias claude='claude-code'
    EOF
    
    # Setup Claude Code
    echo "Setting up Claude Code..."
    mkdir -p ~/.claude/agents ~/.config/claude-code
    
    # Copy Claude agents from repository if they exist
    if [ -d "/home/coder/workspace/.claude/agents" ]; then
      echo "Installing Claude agents..."
      cp -r /home/coder/workspace/.claude/agents/* ~/.claude/agents/
    fi
    
    # Copy Claude configuration if it exists
    if [ -f "/home/coder/workspace/.claude.json" ]; then
      cp /home/coder/workspace/.claude.json ~/.claude.json
    fi
    
    # Install Docker Compose if Docker is enabled
    if [ "${data.coder_parameter.enable_docker.value}" = "true" ]; then
      if ! command -v docker-compose &> /dev/null; then
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
      fi
    fi
    
    echo "✅ Workspace setup complete!"
    echo "🤖 Claude Code is available - run 'claude' to start"
  EOT

  metadata {
    display_name = "CPU Cores"
    key          = "cpu_cores"
    script       = "echo ${data.coder_parameter.cpu_cores.value}"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory"
    key          = "memory_gb"
    script       = "echo ${data.coder_parameter.memory_gb.value} GB"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Disk"
    key          = "disk"
    script       = "df -h /home/coder | tail -1 | awk '{print $3 \"/\" $2}'"
    interval     = 60
    timeout      = 1
  }
}

resource "docker_volume" "workspace" {
  name = "coder-${data.coder_workspace.me.id}-workspace"
}

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}"
  build {
    context = "."
    build_args = {
      USER = "coder"
    }
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(".", "**") : filesha1(f)]))
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.name
  
  cpu_shares = data.coder_parameter.cpu_cores.value * 1024
  memory     = data.coder_parameter.memory_gb.value * 1024
  
  hostname = "coder-${data.coder_workspace.me.name}"
  
  entrypoint = ["sh", "-c", coder_agent.main.init_script]
  
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "WORKSPACE_NAME=${data.coder_workspace.me.name}",
    "WORKSPACE_OWNER=${data.coder_workspace.me.owner}",
  ]
  
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.workspace.name
  }
  
  # Enable Docker in Docker if requested
  dynamic "volumes" {
    for_each = data.coder_parameter.enable_docker.value ? [1] : []
    content {
      host_path      = "/var/run/docker.sock"
      container_path = "/var/run/docker.sock"
    }
  }
  
  # Add privileged mode if Docker is enabled
  privileged = data.coder_parameter.enable_docker.value
  
  # Add capabilities
  capabilities {
    add = data.coder_parameter.enable_docker.value ? ["SYS_PTRACE", "SYS_ADMIN"] : ["SYS_PTRACE"]
  }
}

resource "coder_metadata" "container_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id

  item {
    key   = "Container ID"
    value = substr(docker_container.workspace[0].id, 0, 12)
  }
  
  item {
    key   = "Docker Enabled"
    value = data.coder_parameter.enable_docker.value ? "Yes" : "No"
  }
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337/?folder=/home/coder/workspace"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "terminal" {
  agent_id     = coder_agent.main.id
  slug         = "terminal"
  display_name = "Terminal"
  icon         = "/icon/terminal.svg"
  command      = "bash"
}

# Port forwarding for common development ports
resource "coder_app" "port_3000" {
  agent_id     = coder_agent.main.id
  slug         = "app-3000"
  display_name = "App :3000"
  url          = "http://localhost:3000"
  icon         = "/emojis/1f310.png"
  subdomain    = true
  share        = "owner"
}

resource "coder_app" "port_8080" {
  agent_id     = coder_agent.main.id
  slug         = "app-8080"
  display_name = "App :8080"
  url          = "http://localhost:8080"
  icon         = "/emojis/1f310.png"
  subdomain    = true
  share        = "owner"
}