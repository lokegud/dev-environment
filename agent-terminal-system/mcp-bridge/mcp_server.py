#!/usr/bin/env python3
"""
MCP Server Implementation for Agent Terminal Bridge
Provides full MCP protocol compliance for terminal management
"""

import asyncio
import json
import logging
import os
import sys
from typing import Dict, List, Any, Optional, Sequence
from datetime import datetime

# MCP imports
try:
    from mcp import ClientSession, StdioServerTransport
    from mcp.server import Server
    from mcp.types import (
        Tool, 
        TextContent, 
        CallToolRequest, 
        CallToolResult,
        ListToolsRequest,
        ListToolsResult,
        InitializeRequest,
        InitializeResult,
        Capabilities,
        ServerCapabilities,
        ToolCapabilities
    )
except ImportError:
    print("MCP library not found. Install with: pip install mcp", file=sys.stderr)
    sys.exit(1)

from mcp_tools import MCPTerminalTools

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class MCPTerminalServer:
    """MCP Server for Agent Terminal Management"""
    
    def __init__(self):
        self.server = Server("terminal-bridge")
        self.tools_client = None
        self.bridge_url = os.getenv("TERMINAL_BRIDGE_URL", "http://localhost:8000")
        self.auth_token = os.getenv("MCP_AUTH_TOKEN")
        
        # Register MCP handlers
        self._register_handlers()
        
    def _register_handlers(self):
        """Register MCP protocol handlers"""
        
        @self.server.list_tools()
        async def list_tools() -> ListToolsResult:
            """List available tools"""
            tools = []
            
            # Get tools schema from our MCPTerminalTools
            if not self.tools_client:
                await self._initialize_tools_client()
            
            schemas = self.tools_client.get_tools_schema() if self.tools_client else []
            
            for schema in schemas:
                tool = Tool(
                    name=schema["name"],
                    description=schema["description"],
                    inputSchema=schema["parameters"]
                )
                tools.append(tool)
            
            return ListToolsResult(tools=tools)
        
        @self.server.call_tool()
        async def call_tool(name: str, arguments: Dict[str, Any] | None = None) -> CallToolResult:
            """Handle tool calls"""
            logger.info(f"Tool called: {name} with args: {arguments}")
            
            if not self.tools_client:
                await self._initialize_tools_client()
            
            if not self.tools_client:
                return CallToolResult(
                    content=[TextContent(
                        type="text",
                        text=json.dumps({
                            "success": False,
                            "error": "Terminal bridge not available"
                        })
                    )]
                )
            
            try:
                # Call the tool through our tools client
                result = await self.tools_client.call_tool(name, arguments or {})
                
                return CallToolResult(
                    content=[TextContent(
                        type="text", 
                        text=json.dumps(result, indent=2)
                    )]
                )
                
            except Exception as e:
                logger.error(f"Error calling tool {name}: {e}")
                return CallToolResult(
                    content=[TextContent(
                        type="text",
                        text=json.dumps({
                            "success": False,
                            "error": str(e)
                        })
                    )]
                )
    
    async def _initialize_tools_client(self):
        """Initialize the tools client with authentication"""
        try:
            self.tools_client = MCPTerminalTools(
                base_url=self.bridge_url,
                auth_token=self.auth_token
            )
            await self.tools_client.__aenter__()
            logger.info("Tools client initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize tools client: {e}")
            self.tools_client = None
    
    async def run(self):
        """Run the MCP server"""
        logger.info("Starting MCP Terminal Bridge Server")
        
        # Create stdio transport
        transport = StdioServerTransport()
        
        try:
            # Run the server
            await self.server.run(
                transport,
                InitializeResult(
                    protocolVersion="2024-11-05",
                    capabilities=ServerCapabilities(
                        tools=ToolCapabilities()
                    ),
                    serverInfo={
                        "name": "terminal-bridge",
                        "version": "1.0.0"
                    }
                )
            )
        except Exception as e:
            logger.error(f"Server error: {e}")
        finally:
            if self.tools_client:
                await self.tools_client.__aexit__(None, None, None)

# Standalone MCP Server Entry Point
async def main():
    """Main entry point for the MCP server"""
    server = MCPTerminalServer()
    await server.run()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Server shutting down...")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)