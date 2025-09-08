# Coder Development Environment Template

This repository is configured as a Coder template for creating cloud development environments with all necessary tools pre-installed.

## Features

- **Full Development Stack**: Includes Node.js, Python, Go, Rust, and more
- **Docker-in-Docker Support**: Run containers inside your workspace
- **Pre-configured Tools**:
  - GitHub CLI
  - Docker & Docker Compose
  - Kubernetes (kubectl)
  - Terraform
  - Code-server (VS Code in browser)
  - Multiple language runtimes and tools

## Quick Start with Coder

### 1. Deploy to Coder

```bash
# Clone this repository
git clone https://github.com/lokegud/dev-environment.git
cd dev-environment

# Create template in Coder
coder template create dev-environment

# Or update existing template
coder template push dev-environment
```

### 2. Create a Workspace

```bash
# Create a new workspace from this template
coder create my-workspace --template dev-environment
```

### 3. Access Your Workspace

- **VS Code Browser**: Available at your workspace URL
- **Terminal**: SSH access via `coder ssh my-workspace`
- **Port Forwarding**: Automatic forwarding for ports 3000, 5000, 8000, 8080, 9000

## Template Parameters

When creating a workspace, you can customize:

- **CPU Cores**: 1-16 cores (default: 4)
- **Memory**: 1-32 GB (default: 8)
- **Disk Size**: 10-500 GB (default: 50)
- **Docker Support**: Enable/disable Docker-in-Docker
- **Git Repository**: Auto-clone a repository on startup

## Workspace Structure

```
/home/coder/workspace/
├── agent-terminal-system/     # Agent Terminal System project
├── mcp-server-platform/       # MCP Server Platform
└── ...                        # Your project files
```

## Available Commands

- `agent-term` - Navigate to Agent Terminal System
- `mcp-server` - Navigate to MCP Server Platform
- `dc` - Docker Compose shortcut
- `k` - Kubectl shortcut

## Development Workflow

1. **Start Services**:
   ```bash
   cd agent-terminal-system
   docker-compose up -d
   ```

2. **Check Logs**:
   ```bash
   docker-compose logs -f
   ```

3. **Access Applications**:
   - Port 3000: Frontend applications
   - Port 8080: Backend services
   - Port 9000: Admin interfaces

## Using with GitHub Codespaces

This repository also works with GitHub Codespaces. The `.devcontainer` configuration ensures a consistent environment across both Coder and Codespaces.

## Customization

### Modify the Template

Edit `main.tf` to:
- Add more applications
- Change default parameters
- Add additional software
- Configure different IDEs

### Update the Docker Image

Edit `Dockerfile` to:
- Install additional tools
- Configure different versions
- Add custom configurations

## Troubleshooting

### Docker Issues
If Docker-in-Docker isn't working:
```bash
# Check Docker socket permissions
ls -la /var/run/docker.sock

# Test Docker
docker run hello-world
```

### Port Forwarding
Ports are automatically forwarded. Access them via:
- Coder Dashboard → Your Workspace → Apps
- Or use `coder port-forward my-workspace 3000:3000`

## Support

- [Coder Documentation](https://coder.com/docs)
- [Template Examples](https://github.com/coder/coder/tree/main/examples/templates)
- [GitHub Issues](https://github.com/lokegud/dev-environment/issues)