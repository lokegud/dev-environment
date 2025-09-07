#!/usr/bin/env python3
"""
Simple MCP Terminal Bridge - Working Version
Integrates with your existing terminal system
"""
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
import subprocess
import json
import uuid
import time
from typing import Dict, Any
import os

app = FastAPI(title="MCP Terminal Bridge", version="1.0.0")

# In-memory storage for active terminals
active_terminals: Dict[str, Dict[str, Any]] = {}

def run_command(cmd: str, timeout: int = 30) -> tuple:
    """Execute a shell command"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return False, "", "Command timed out"

@app.get("/")
async def root():
    return {"message": "MCP Terminal Bridge", "status": "running", "active_terminals": len(active_terminals)}

@app.get("/health")
async def health():
    return {"status": "healthy", "timestamp": time.time()}

@app.post("/terminals/create")
async def create_terminal(agent_id: str):
    """Create a new terminal for an agent"""
    terminal_id = str(uuid.uuid4())
    
    # Use your existing script to create terminal
    cmd = f"/home/loke/create-agent-terminal.sh {agent_id}-{terminal_id[:8]}"
    success, stdout, stderr = run_command(cmd)
    
    if not success:
        raise HTTPException(status_code=500, detail=f"Failed to create terminal: {stderr}")
    
    # Extract container ID from output
    container_name = f"agent-terminal-{agent_id}-{terminal_id[:8]}"
    
    # Store terminal info
    active_terminals[terminal_id] = {
        "agent_id": agent_id,
        "container_name": container_name,
        "created_at": time.time(),
        "status": "running"
    }
    
    return {
        "terminal_id": terminal_id,
        "agent_id": agent_id,
        "container_name": container_name,
        "status": "created"
    }

@app.post("/terminals/{terminal_id}/execute")
async def execute_command(terminal_id: str, command: str):
    """Execute a command in the terminal"""
    if terminal_id not in active_terminals:
        raise HTTPException(status_code=404, detail="Terminal not found")
    
    terminal = active_terminals[terminal_id]
    container_name = terminal["container_name"]
    
    # Execute command in the container
    cmd = f"docker exec {container_name} bash -c '{command}'"
    success, stdout, stderr = run_command(cmd)
    
    return {
        "terminal_id": terminal_id,
        "command": command,
        "success": success,
        "stdout": stdout,
        "stderr": stderr,
        "timestamp": time.time()
    }

@app.get("/terminals/{terminal_id}/logs")
async def get_logs(terminal_id: str, lines: int = 50):
    """Get logs from the terminal"""
    if terminal_id not in active_terminals:
        raise HTTPException(status_code=404, detail="Terminal not found")
    
    terminal = active_terminals[terminal_id]
    container_name = terminal["container_name"]
    
    # Get container logs
    cmd = f"docker logs --tail {lines} {container_name}"
    success, stdout, stderr = run_command(cmd)
    
    return {
        "terminal_id": terminal_id,
        "logs": stdout,
        "stderr": stderr,
        "timestamp": time.time()
    }

@app.get("/terminals")
async def list_terminals():
    """List all active terminals"""
    return {"terminals": active_terminals}

@app.delete("/terminals/{terminal_id}")
async def destroy_terminal(terminal_id: str):
    """Destroy a terminal"""
    if terminal_id not in active_terminals:
        raise HTTPException(status_code=404, detail="Terminal not found")
    
    terminal = active_terminals[terminal_id]
    container_name = terminal["container_name"]
    
    # Stop and remove the container
    cmd = f"docker stop {container_name} && docker rm {container_name}"
    success, stdout, stderr = run_command(cmd)
    
    # Remove from active terminals
    del active_terminals[terminal_id]
    
    return {
        "terminal_id": terminal_id,
        "status": "destroyed",
        "success": success
    }

@app.get("/terminals/{terminal_id}/status")
async def get_terminal_status(terminal_id: str):
    """Get terminal status"""
    if terminal_id not in active_terminals:
        raise HTTPException(status_code=404, detail="Terminal not found")
    
    terminal = active_terminals[terminal_id]
    container_name = terminal["container_name"]
    
    # Check if container is running
    cmd = f"docker ps --filter name={container_name} --format '{{{{.Status}}}}'"
    success, stdout, stderr = run_command(cmd)
    
    is_running = success and stdout.strip() != ""
    
    return {
        "terminal_id": terminal_id,
        "agent_id": terminal["agent_id"],
        "container_name": container_name,
        "is_running": is_running,
        "container_status": stdout.strip(),
        "created_at": terminal["created_at"]
    }

# Demo endpoints
@app.post("/demo/test-integration")
async def demo_test_integration():
    """Demo: Test full integration workflow"""
    agent_id = f"demo-agent-{int(time.time())}"
    
    # 1. Create terminal
    terminal = await create_terminal(agent_id)
    terminal_id = terminal["terminal_id"]
    
    # 2. Wait a moment for container to start
    time.sleep(2)
    
    # 3. Execute test commands
    commands = [
        "echo 'MCP Bridge Integration Test'",
        "python3 --version",
        "whoami",
        "pwd",
        "ls -la"
    ]
    
    results = []
    for cmd in commands:
        result = await execute_command(terminal_id, cmd)
        results.append({"command": cmd, "output": result["stdout"]})
    
    # 4. Get logs
    logs = await get_logs(terminal_id)
    
    # 5. Clean up
    await destroy_terminal(terminal_id)
    
    return {
        "demo": "MCP Terminal Bridge Integration Test",
        "agent_id": agent_id,
        "terminal_id": terminal_id,
        "test_results": results,
        "logs_sample": logs["logs"][-500:] if logs["logs"] else "",
        "status": "completed"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)