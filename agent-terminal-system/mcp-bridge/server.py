#!/usr/bin/env python3
"""
MCP Terminal Bridge Server
Provides an MCP-compatible interface for agent terminal management
"""

import asyncio
import json
import logging
import os
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import jwt
import docker
import redis
import websockets
from fastapi import FastAPI, HTTPException, Depends, WebSocket
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn
from contextlib import asynccontextmanager

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
class Config:
    JWT_SECRET = os.getenv("JWT_SECRET", "mcp-terminal-bridge-secret")
    JWT_ALGORITHM = "HS256"
    JWT_EXPIRE_HOURS = 24
    REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
    ELASTICSEARCH_URL = os.getenv("ELASTICSEARCH_URL", "http://localhost:9200")
    TERMINAL_IMAGE = "minimal-agent-terminal:latest"
    LOG_BASE_DIR = "/tmp/agent-logs"
    MAX_TERMINALS_PER_AGENT = 5
    TERMINAL_TIMEOUT_HOURS = 4

config = Config()

# Data models
class TerminalCreateRequest(BaseModel):
    agent_id: str
    command: Optional[str] = "bash"
    environment: Optional[Dict[str, str]] = None
    timeout_hours: Optional[int] = 4

class TerminalExecuteRequest(BaseModel):
    command: str
    timeout: Optional[int] = 30

class TerminalResponse(BaseModel):
    terminal_id: str
    agent_id: str
    status: str
    created_at: str
    container_id: str
    log_path: str

class ExecuteResponse(BaseModel):
    output: str
    error: str
    exit_code: int
    execution_time: float

# Global state
terminals: Dict[str, Dict] = {}
docker_client = None
redis_client = None
security = HTTPBearer()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager"""
    global docker_client, redis_client
    
    # Initialize Docker client
    try:
        docker_client = docker.from_env()
        logger.info("Docker client initialized")
    except Exception as e:
        logger.error(f"Failed to initialize Docker client: {e}")
        raise
    
    # Initialize Redis client
    try:
        redis_client = redis.from_url(config.REDIS_URL)
        redis_client.ping()
        logger.info("Redis client initialized")
    except Exception as e:
        logger.error(f"Failed to initialize Redis client: {e}")
        raise
    
    # Create log directory
    os.makedirs(config.LOG_BASE_DIR, exist_ok=True)
    
    # Start cleanup task
    cleanup_task = asyncio.create_task(cleanup_expired_terminals())
    
    yield
    
    # Cleanup
    cleanup_task.cancel()
    try:
        await cleanup_task
    except asyncio.CancelledError:
        pass

# Initialize FastAPI app
app = FastAPI(
    title="MCP Terminal Bridge",
    description="MCP-compatible interface for agent terminal management",
    version="1.0.0",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Authentication utilities
def create_access_token(data: Dict[str, Any]) -> str:
    """Create a JWT access token"""
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(hours=config.JWT_EXPIRE_HOURS)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, config.JWT_SECRET, algorithm=config.JWT_ALGORITHM)

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)) -> Dict[str, Any]:
    """Verify JWT token"""
    try:
        payload = jwt.decode(credentials.credentials, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")

# Terminal management functions
def create_agent_terminal(agent_id: str, command: str = "bash", environment: Dict[str, str] = None) -> Dict[str, Any]:
    """Create a new agent terminal container"""
    terminal_id = str(uuid.uuid4())
    
    # Check terminal limits
    agent_terminals = [t for t in terminals.values() if t["agent_id"] == agent_id and t["status"] == "running"]
    if len(agent_terminals) >= config.MAX_TERMINALS_PER_AGENT:
        raise HTTPException(status_code=429, detail=f"Maximum terminals ({config.MAX_TERMINALS_PER_AGENT}) reached for agent")
    
    # Create log directory
    log_dir = os.path.join(config.LOG_BASE_DIR, agent_id, terminal_id)
    os.makedirs(log_dir, exist_ok=True)
    
    # Prepare environment variables
    env_vars = {
        "AGENT_ID": agent_id,
        "TERMINAL_ID": terminal_id,
        "LOG_DIR": "/tmp/logs"
    }
    if environment:
        env_vars.update(environment)
    
    try:
        # Create and start container
        container = docker_client.containers.run(
            config.TERMINAL_IMAGE,
            command=f'bash -c "echo \\"=== Agent Terminal Started ===\\" && echo \\"Agent ID: {agent_id}\\" && echo \\"Terminal ID: {terminal_id}\\" && echo \\"Timestamp: $(date)\\" && echo \\"Working Directory: $(pwd)\\" && echo \\"User: $(whoami)\\" && echo && echo \\"Terminal ready for commands\\" && echo \\"$(date): Terminal {terminal_id} started\\" > /tmp/logs/session.log && {command}"',
            environment=env_vars,
            volumes={log_dir: {"bind": "/tmp/logs", "mode": "rw"}},
            detach=True,
            name=f"mcp-terminal-{terminal_id}",
            network_mode="bridge",
            mem_limit="512m",
            cpu_quota=50000,  # 50% CPU
            remove=False
        )
        
        terminal_info = {
            "terminal_id": terminal_id,
            "agent_id": agent_id,
            "container_id": container.id,
            "status": "running",
            "created_at": datetime.utcnow().isoformat(),
            "log_dir": log_dir,
            "command": command,
            "expires_at": (datetime.utcnow() + timedelta(hours=config.TERMINAL_TIMEOUT_HOURS)).isoformat()
        }
        
        terminals[terminal_id] = terminal_info
        
        # Store in Redis for persistence
        redis_client.setex(
            f"terminal:{terminal_id}",
            config.TERMINAL_TIMEOUT_HOURS * 3600,
            json.dumps(terminal_info)
        )
        
        logger.info(f"Created terminal {terminal_id} for agent {agent_id}")
        return terminal_info
        
    except Exception as e:
        logger.error(f"Failed to create terminal for agent {agent_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to create terminal: {str(e)}")

def execute_command_in_terminal(terminal_id: str, command: str, timeout: int = 30) -> ExecuteResponse:
    """Execute a command in an existing terminal"""
    if terminal_id not in terminals:
        raise HTTPException(status_code=404, detail="Terminal not found")
    
    terminal = terminals[terminal_id]
    if terminal["status"] != "running":
        raise HTTPException(status_code=400, detail="Terminal not running")
    
    try:
        container = docker_client.containers.get(terminal["container_id"])
        
        start_time = datetime.now()
        result = container.exec_run(
            command,
            stdout=True,
            stderr=True,
            stream=False,
            timeout=timeout
        )
        execution_time = (datetime.now() - start_time).total_seconds()
        
        # Log the command execution
        log_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "terminal_id": terminal_id,
            "agent_id": terminal["agent_id"],
            "command": command,
            "exit_code": result.exit_code,
            "execution_time": execution_time
        }
        
        redis_client.lpush(f"terminal:{terminal_id}:commands", json.dumps(log_entry))
        redis_client.expire(f"terminal:{terminal_id}:commands", config.TERMINAL_TIMEOUT_HOURS * 3600)
        
        return ExecuteResponse(
            output=result.output.decode('utf-8') if result.output else "",
            error="",
            exit_code=result.exit_code,
            execution_time=execution_time
        )
        
    except Exception as e:
        logger.error(f"Failed to execute command in terminal {terminal_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Command execution failed: {str(e)}")

def get_terminal_logs(terminal_id: str, lines: int = 100) -> str:
    """Get logs from a terminal"""
    if terminal_id not in terminals:
        raise HTTPException(status_code=404, detail="Terminal not found")
    
    terminal = terminals[terminal_id]
    
    try:
        container = docker_client.containers.get(terminal["container_id"])
        logs = container.logs(tail=lines, timestamps=True)
        return logs.decode('utf-8')
    except Exception as e:
        logger.error(f"Failed to get logs for terminal {terminal_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get logs: {str(e)}")

def destroy_terminal(terminal_id: str) -> bool:
    """Destroy a terminal and its container"""
    if terminal_id not in terminals:
        raise HTTPException(status_code=404, detail="Terminal not found")
    
    terminal = terminals[terminal_id]
    
    try:
        # Stop and remove container
        container = docker_client.containers.get(terminal["container_id"])
        container.stop(timeout=10)
        container.remove()
        
        # Update status
        terminals[terminal_id]["status"] = "destroyed"
        
        # Remove from Redis
        redis_client.delete(f"terminal:{terminal_id}")
        redis_client.delete(f"terminal:{terminal_id}:commands")
        
        logger.info(f"Destroyed terminal {terminal_id}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to destroy terminal {terminal_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to destroy terminal: {str(e)}")

async def cleanup_expired_terminals():
    """Background task to cleanup expired terminals"""
    while True:
        try:
            current_time = datetime.utcnow()
            expired_terminals = []
            
            for terminal_id, terminal in terminals.items():
                if terminal["status"] == "running":
                    expires_at = datetime.fromisoformat(terminal["expires_at"])
                    if current_time > expires_at:
                        expired_terminals.append(terminal_id)
            
            for terminal_id in expired_terminals:
                try:
                    destroy_terminal(terminal_id)
                    logger.info(f"Cleaned up expired terminal {terminal_id}")
                except Exception as e:
                    logger.error(f"Failed to cleanup terminal {terminal_id}: {e}")
            
            await asyncio.sleep(300)  # Check every 5 minutes
            
        except Exception as e:
            logger.error(f"Error in cleanup task: {e}")
            await asyncio.sleep(60)

# API Routes
@app.post("/auth/token")
async def create_token(agent_id: str):
    """Create an authentication token for an agent"""
    token_data = {"agent_id": agent_id, "iat": datetime.utcnow().timestamp()}
    token = create_access_token(token_data)
    return {"access_token": token, "token_type": "bearer", "expires_in": config.JWT_EXPIRE_HOURS * 3600}

@app.post("/terminals", response_model=TerminalResponse)
async def create_terminal(request: TerminalCreateRequest, token_data: Dict = Depends(verify_token)):
    """Create a new agent terminal"""
    # Verify agent_id matches token
    if request.agent_id != token_data.get("agent_id"):
        raise HTTPException(status_code=403, detail="Agent ID mismatch")
    
    terminal_info = create_agent_terminal(
        request.agent_id,
        request.command or "bash",
        request.environment or {}
    )
    
    return TerminalResponse(
        terminal_id=terminal_info["terminal_id"],
        agent_id=terminal_info["agent_id"],
        status=terminal_info["status"],
        created_at=terminal_info["created_at"],
        container_id=terminal_info["container_id"],
        log_path=terminal_info["log_dir"]
    )

@app.post("/terminals/{terminal_id}/execute", response_model=ExecuteResponse)
async def execute_command(terminal_id: str, request: TerminalExecuteRequest, token_data: Dict = Depends(verify_token)):
    """Execute a command in a terminal"""
    # Verify the agent owns this terminal
    if terminal_id not in terminals:
        raise HTTPException(status_code=404, detail="Terminal not found")
    
    terminal = terminals[terminal_id]
    if terminal["agent_id"] != token_data.get("agent_id"):
        raise HTTPException(status_code=403, detail="Access denied")
    
    return execute_command_in_terminal(terminal_id, request.command, request.timeout or 30)

@app.get("/terminals/{terminal_id}/logs")
async def get_logs(terminal_id: str, lines: int = 100, token_data: Dict = Depends(verify_token)):
    """Get terminal logs"""
    # Verify the agent owns this terminal
    if terminal_id not in terminals:
        raise HTTPException(status_code=404, detail="Terminal not found")
    
    terminal = terminals[terminal_id]
    if terminal["agent_id"] != token_data.get("agent_id"):
        raise HTTPException(status_code=403, detail="Access denied")
    
    logs = get_terminal_logs(terminal_id, lines)
    return {"logs": logs}

@app.delete("/terminals/{terminal_id}")
async def delete_terminal(terminal_id: str, token_data: Dict = Depends(verify_token)):
    """Destroy a terminal"""
    # Verify the agent owns this terminal
    if terminal_id not in terminals:
        raise HTTPException(status_code=404, detail="Terminal not found")
    
    terminal = terminals[terminal_id]
    if terminal["agent_id"] != token_data.get("agent_id"):
        raise HTTPException(status_code=403, detail="Access denied")
    
    success = destroy_terminal(terminal_id)
    return {"success": success}

@app.get("/terminals")
async def list_terminals(token_data: Dict = Depends(verify_token)):
    """List agent's terminals"""
    agent_id = token_data.get("agent_id")
    agent_terminals = [t for t in terminals.values() if t["agent_id"] == agent_id]
    return {"terminals": agent_terminals}

# WebSocket for real-time streaming
@app.websocket("/terminals/{terminal_id}/stream")
async def terminal_stream(websocket: WebSocket, terminal_id: str, token: str = None):
    """WebSocket endpoint for real-time terminal streaming"""
    await websocket.accept()
    
    try:
        # Verify token
        if not token:
            await websocket.send_json({"error": "Token required"})
            await websocket.close()
            return
        
        try:
            payload = jwt.decode(token, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM])
            agent_id = payload.get("agent_id")
        except jwt.JWTError:
            await websocket.send_json({"error": "Invalid token"})
            await websocket.close()
            return
        
        # Verify terminal ownership
        if terminal_id not in terminals:
            await websocket.send_json({"error": "Terminal not found"})
            await websocket.close()
            return
        
        terminal = terminals[terminal_id]
        if terminal["agent_id"] != agent_id:
            await websocket.send_json({"error": "Access denied"})
            await websocket.close()
            return
        
        # Stream logs
        container = docker_client.containers.get(terminal["container_id"])
        log_stream = container.logs(stream=True, follow=True, timestamps=True)
        
        for log_line in log_stream:
            try:
                await websocket.send_text(log_line.decode('utf-8'))
            except:
                break
                
    except Exception as e:
        logger.error(f"WebSocket error for terminal {terminal_id}: {e}")
        await websocket.close()

# Health check
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "terminals": len([t for t in terminals.values() if t["status"] == "running"]),
        "docker_status": "connected" if docker_client else "disconnected",
        "redis_status": "connected" if redis_client else "disconnected"
    }

if __name__ == "__main__":
    uvicorn.run(
        "server:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info"
    )