#!/usr/bin/env python3
"""
MCP Tools Implementation for Terminal Management
Provides MCP-compatible tools for managing agent terminals
"""

import asyncio
import json
import logging
import os
from typing import Dict, List, Any, Optional
import aiohttp
from datetime import datetime

logger = logging.getLogger(__name__)

class MCPTerminalTools:
    """MCP-compatible tools for terminal management"""
    
    def __init__(self, base_url: str = "http://localhost:8000", auth_token: str = None):
        self.base_url = base_url.rstrip('/')
        self.auth_token = auth_token
        self.session = None
        
    async def __aenter__(self):
        """Async context manager entry"""
        self.session = aiohttp.ClientSession(
            headers={"Authorization": f"Bearer {self.auth_token}"} if self.auth_token else {}
        )
        return self
        
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        if self.session:
            await self.session.close()

    def get_tools_schema(self) -> List[Dict[str, Any]]:
        """Return MCP tools schema"""
        return [
            {
                "name": "create_terminal",
                "description": "Create a new agent terminal with isolated environment",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "agent_id": {
                            "type": "string",
                            "description": "Unique identifier for the agent"
                        },
                        "command": {
                            "type": "string",
                            "description": "Initial command to run in terminal (default: bash)",
                            "default": "bash"
                        },
                        "environment": {
                            "type": "object",
                            "description": "Environment variables to set in terminal",
                            "additionalProperties": {"type": "string"}
                        },
                        "timeout_hours": {
                            "type": "integer",
                            "description": "Terminal timeout in hours (default: 4)",
                            "minimum": 1,
                            "maximum": 24,
                            "default": 4
                        }
                    },
                    "required": ["agent_id"]
                }
            },
            {
                "name": "execute_command",
                "description": "Execute a command in an existing terminal",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "terminal_id": {
                            "type": "string",
                            "description": "Terminal identifier returned from create_terminal"
                        },
                        "command": {
                            "type": "string",
                            "description": "Command to execute in the terminal"
                        },
                        "timeout": {
                            "type": "integer",
                            "description": "Command timeout in seconds (default: 30)",
                            "minimum": 1,
                            "maximum": 300,
                            "default": 30
                        }
                    },
                    "required": ["terminal_id", "command"]
                }
            },
            {
                "name": "get_logs",
                "description": "Retrieve logs from a terminal",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "terminal_id": {
                            "type": "string",
                            "description": "Terminal identifier"
                        },
                        "lines": {
                            "type": "integer",
                            "description": "Number of log lines to retrieve (default: 100)",
                            "minimum": 1,
                            "maximum": 10000,
                            "default": 100
                        },
                        "stream": {
                            "type": "boolean",
                            "description": "Whether to stream logs in real-time (default: false)",
                            "default": false
                        }
                    },
                    "required": ["terminal_id"]
                }
            },
            {
                "name": "destroy_terminal",
                "description": "Destroy a terminal and clean up its resources",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "terminal_id": {
                            "type": "string",
                            "description": "Terminal identifier to destroy"
                        }
                    },
                    "required": ["terminal_id"]
                }
            },
            {
                "name": "list_terminals",
                "description": "List all terminals for the authenticated agent",
                "parameters": {
                    "type": "object",
                    "properties": {}
                }
            },
            {
                "name": "get_terminal_status",
                "description": "Get detailed status information for a terminal",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "terminal_id": {
                            "type": "string",
                            "description": "Terminal identifier"
                        }
                    },
                    "required": ["terminal_id"]
                }
            }
        ]

    async def create_terminal(self, agent_id: str, command: str = "bash", 
                            environment: Optional[Dict[str, str]] = None, 
                            timeout_hours: int = 4) -> Dict[str, Any]:
        """Create a new agent terminal"""
        if not self.session:
            raise RuntimeError("Tools not initialized. Use async context manager.")
            
        payload = {
            "agent_id": agent_id,
            "command": command,
            "environment": environment or {},
            "timeout_hours": timeout_hours
        }
        
        try:
            async with self.session.post(f"{self.base_url}/terminals", json=payload) as response:
                if response.status == 200:
                    result = await response.json()
                    logger.info(f"Created terminal {result['terminal_id']} for agent {agent_id}")
                    return {
                        "success": True,
                        "terminal_id": result["terminal_id"],
                        "agent_id": result["agent_id"],
                        "status": result["status"],
                        "created_at": result["created_at"],
                        "container_id": result["container_id"],
                        "log_path": result["log_path"]
                    }
                else:
                    error_detail = await response.text()
                    logger.error(f"Failed to create terminal: {response.status} - {error_detail}")
                    return {
                        "success": False,
                        "error": f"HTTP {response.status}: {error_detail}"
                    }
        except Exception as e:
            logger.error(f"Exception creating terminal: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    async def execute_command(self, terminal_id: str, command: str, timeout: int = 30) -> Dict[str, Any]:
        """Execute a command in a terminal"""
        if not self.session:
            raise RuntimeError("Tools not initialized. Use async context manager.")
            
        payload = {
            "command": command,
            "timeout": timeout
        }
        
        try:
            async with self.session.post(f"{self.base_url}/terminals/{terminal_id}/execute", json=payload) as response:
                if response.status == 200:
                    result = await response.json()
                    logger.info(f"Executed command in terminal {terminal_id}: {command}")
                    return {
                        "success": True,
                        "output": result["output"],
                        "error": result["error"],
                        "exit_code": result["exit_code"],
                        "execution_time": result["execution_time"]
                    }
                else:
                    error_detail = await response.text()
                    logger.error(f"Failed to execute command: {response.status} - {error_detail}")
                    return {
                        "success": False,
                        "error": f"HTTP {response.status}: {error_detail}"
                    }
        except Exception as e:
            logger.error(f"Exception executing command: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    async def get_logs(self, terminal_id: str, lines: int = 100, stream: bool = False) -> Dict[str, Any]:
        """Get logs from a terminal"""
        if not self.session:
            raise RuntimeError("Tools not initialized. Use async context manager.")
            
        if stream:
            # For streaming logs, we would use WebSocket connection
            return await self._stream_logs(terminal_id)
        
        try:
            params = {"lines": lines}
            async with self.session.get(f"{self.base_url}/terminals/{terminal_id}/logs", params=params) as response:
                if response.status == 200:
                    result = await response.json()
                    return {
                        "success": True,
                        "logs": result["logs"],
                        "lines_returned": len(result["logs"].split('\n'))
                    }
                else:
                    error_detail = await response.text()
                    logger.error(f"Failed to get logs: {response.status} - {error_detail}")
                    return {
                        "success": False,
                        "error": f"HTTP {response.status}: {error_detail}"
                    }
        except Exception as e:
            logger.error(f"Exception getting logs: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    async def _stream_logs(self, terminal_id: str) -> Dict[str, Any]:
        """Stream logs from a terminal using WebSocket"""
        try:
            import websockets
            
            ws_url = f"ws{self.base_url[4:]}/terminals/{terminal_id}/stream"
            if self.auth_token:
                ws_url += f"?token={self.auth_token}"
            
            log_buffer = []
            
            async with websockets.connect(ws_url) as websocket:
                # Stream for a limited time or until connection closes
                timeout_count = 0
                while timeout_count < 30:  # 30 second timeout
                    try:
                        message = await asyncio.wait_for(websocket.recv(), timeout=1.0)
                        log_buffer.append(message)
                        timeout_count = 0
                    except asyncio.TimeoutError:
                        timeout_count += 1
                        continue
                    except websockets.exceptions.ConnectionClosed:
                        break
            
            return {
                "success": True,
                "logs": "\n".join(log_buffer),
                "streaming": True,
                "lines_streamed": len(log_buffer)
            }
            
        except Exception as e:
            logger.error(f"Exception streaming logs: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    async def destroy_terminal(self, terminal_id: str) -> Dict[str, Any]:
        """Destroy a terminal"""
        if not self.session:
            raise RuntimeError("Tools not initialized. Use async context manager.")
            
        try:
            async with self.session.delete(f"{self.base_url}/terminals/{terminal_id}") as response:
                if response.status == 200:
                    result = await response.json()
                    logger.info(f"Destroyed terminal {terminal_id}")
                    return {
                        "success": True,
                        "terminal_id": terminal_id,
                        "destroyed": result["success"]
                    }
                else:
                    error_detail = await response.text()
                    logger.error(f"Failed to destroy terminal: {response.status} - {error_detail}")
                    return {
                        "success": False,
                        "error": f"HTTP {response.status}: {error_detail}"
                    }
        except Exception as e:
            logger.error(f"Exception destroying terminal: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    async def list_terminals(self) -> Dict[str, Any]:
        """List all terminals for the agent"""
        if not self.session:
            raise RuntimeError("Tools not initialized. Use async context manager.")
            
        try:
            async with self.session.get(f"{self.base_url}/terminals") as response:
                if response.status == 200:
                    result = await response.json()
                    return {
                        "success": True,
                        "terminals": result["terminals"],
                        "count": len(result["terminals"])
                    }
                else:
                    error_detail = await response.text()
                    logger.error(f"Failed to list terminals: {response.status} - {error_detail}")
                    return {
                        "success": False,
                        "error": f"HTTP {response.status}: {error_detail}"
                    }
        except Exception as e:
            logger.error(f"Exception listing terminals: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    async def get_terminal_status(self, terminal_id: str) -> Dict[str, Any]:
        """Get detailed status for a specific terminal"""
        terminals = await self.list_terminals()
        if not terminals["success"]:
            return terminals
        
        for terminal in terminals["terminals"]:
            if terminal["terminal_id"] == terminal_id:
                # Get recent logs for additional context
                logs = await self.get_logs(terminal_id, lines=10)
                
                return {
                    "success": True,
                    "terminal": terminal,
                    "recent_logs": logs.get("logs", "") if logs["success"] else "Unable to fetch logs"
                }
        
        return {
            "success": False,
            "error": "Terminal not found"
        }

    async def call_tool(self, tool_name: str, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Generic tool caller - MCP interface"""
        tool_methods = {
            "create_terminal": self.create_terminal,
            "execute_command": self.execute_command,
            "get_logs": self.get_logs,
            "destroy_terminal": self.destroy_terminal,
            "list_terminals": self.list_terminals,
            "get_terminal_status": self.get_terminal_status
        }
        
        if tool_name not in tool_methods:
            return {
                "success": False,
                "error": f"Unknown tool: {tool_name}"
            }
        
        try:
            method = tool_methods[tool_name]
            return await method(**parameters)
        except Exception as e:
            logger.error(f"Error calling tool {tool_name}: {e}")
            return {
                "success": False,
                "error": str(e)
            }


# Example usage and testing
async def main():
    """Example usage of MCP Terminal Tools"""
    import os
    
    # This would normally come from MCP server configuration
    auth_token = os.getenv("MCP_AUTH_TOKEN")
    
    async with MCPTerminalTools(auth_token=auth_token) as tools:
        # Create a terminal
        result = await tools.create_terminal(
            agent_id="example-agent",
            command="bash",
            environment={"PYTHON_PATH": "/usr/bin/python3"}
        )
        
        if result["success"]:
            terminal_id = result["terminal_id"]
            print(f"Created terminal: {terminal_id}")
            
            # Execute a command
            cmd_result = await tools.execute_command(terminal_id, "echo 'Hello from MCP!'")
            if cmd_result["success"]:
                print(f"Command output: {cmd_result['output']}")
            
            # Get logs
            logs = await tools.get_logs(terminal_id, lines=50)
            if logs["success"]:
                print(f"Terminal logs:\n{logs['logs']}")
            
            # List terminals
            terminals = await tools.list_terminals()
            if terminals["success"]:
                print(f"Active terminals: {terminals['count']}")
            
            # Clean up
            cleanup = await tools.destroy_terminal(terminal_id)
            if cleanup["success"]:
                print("Terminal destroyed")
        else:
            print(f"Failed to create terminal: {result['error']}")

if __name__ == "__main__":
    asyncio.run(main())