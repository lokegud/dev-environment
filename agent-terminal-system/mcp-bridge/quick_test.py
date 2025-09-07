#!/usr/bin/env python3
"""
Quick integration test to verify MCP bridge works with existing terminal system
"""

import json
import time
import requests
import jwt
import asyncio
from mcp_tools import MCPTerminalTools

# Configuration
BRIDGE_URL = "http://localhost:8000"
JWT_SECRET = "mcp-terminal-bridge-secret"
TEST_AGENT = "quick-test-agent"

def create_test_token():
    """Create test JWT token"""
    payload = {
        "agent_id": TEST_AGENT,
        "iat": time.time()
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")

def test_bridge_direct():
    """Test bridge server directly"""
    print("Testing MCP Bridge Direct Integration...")
    
    # Create auth token
    token = create_test_token()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    
    try:
        # Test health
        response = requests.get(f"{BRIDGE_URL}/health", timeout=5)
        if response.status_code != 200:
            print(f"❌ Health check failed: {response.status_code}")
            return False
        
        health = response.json()
        print(f"✅ Bridge healthy - Docker: {health.get('docker_status')}, Redis: {health.get('redis_status')}")
        
        # Create terminal
        payload = {
            "agent_id": TEST_AGENT,
            "command": "bash",
            "environment": {"TEST_ENV": "quick_test"},
            "timeout_hours": 1
        }
        
        response = requests.post(f"{BRIDGE_URL}/terminals", json=payload, headers=headers)
        if response.status_code != 200:
            print(f"❌ Terminal creation failed: {response.status_code} - {response.text}")
            return False
        
        terminal_data = response.json()
        terminal_id = terminal_data["terminal_id"]
        print(f"✅ Created terminal: {terminal_id}")
        
        # Execute command
        cmd_payload = {"command": "echo 'Hello from MCP Bridge!'", "timeout": 10}
        response = requests.post(f"{BRIDGE_URL}/terminals/{terminal_id}/execute", json=cmd_payload, headers=headers)
        
        if response.status_code != 200:
            print(f"❌ Command execution failed: {response.status_code} - {response.text}")
            return False
        
        cmd_result = response.json()
        if "Hello from MCP Bridge!" not in cmd_result["output"]:
            print(f"❌ Command output incorrect: {cmd_result}")
            return False
        
        print(f"✅ Command executed successfully: {cmd_result['output'].strip()}")
        
        # Get logs
        response = requests.get(f"{BRIDGE_URL}/terminals/{terminal_id}/logs?lines=20", headers=headers)
        if response.status_code == 200:
            logs_data = response.json()
            print(f"✅ Retrieved {len(logs_data['logs'].split('\\n'))} log lines")
        
        # Cleanup
        response = requests.delete(f"{BRIDGE_URL}/terminals/{terminal_id}", headers=headers)
        if response.status_code == 200:
            print("✅ Terminal cleaned up successfully")
        
        return True
        
    except Exception as e:
        print(f"❌ Bridge test failed: {e}")
        return False

async def test_mcp_tools():
    """Test MCP tools integration"""
    print("\\nTesting MCP Tools Integration...")
    
    token = create_test_token()
    
    try:
        async with MCPTerminalTools(base_url=BRIDGE_URL, auth_token=token) as tools:
            # Test create terminal
            result = await tools.create_terminal(TEST_AGENT, command="bash", environment={"MCP_TEST": "true"})
            if not result["success"]:
                print(f"❌ MCP create terminal failed: {result['error']}")
                return False
            
            terminal_id = result["terminal_id"]
            print(f"✅ MCP created terminal: {terminal_id}")
            
            # Test execute command
            result = await tools.execute_command(terminal_id, "echo $MCP_TEST && python3 --version")
            if not result["success"]:
                print(f"❌ MCP execute failed: {result['error']}")
                return False
            
            if "true" not in result["output"] or "Python" not in result["output"]:
                print(f"❌ MCP command output incorrect: {result}")
                return False
            
            print("✅ MCP command executed successfully")
            
            # Test list terminals
            result = await tools.list_terminals()
            if not result["success"]:
                print(f"❌ MCP list terminals failed: {result['error']}")
                return False
            
            if result["count"] < 1:
                print("❌ MCP terminal not found in list")
                return False
            
            print(f"✅ MCP listed {result['count']} terminals")
            
            # Test get logs
            result = await tools.get_logs(terminal_id, lines=30)
            if not result["success"]:
                print(f"❌ MCP get logs failed: {result['error']}")
                return False
            
            print("✅ MCP retrieved logs successfully")
            
            # Cleanup
            result = await tools.destroy_terminal(terminal_id)
            if not result["success"]:
                print(f"❌ MCP cleanup failed: {result['error']}")
                return False
            
            print("✅ MCP terminal cleaned up successfully")
            
            return True
            
    except Exception as e:
        print(f"❌ MCP tools test failed: {e}")
        return False

def main():
    """Main test runner"""
    print("=" * 60)
    print("MCP Terminal Bridge - Quick Integration Test")
    print("=" * 60)
    
    # Check if server is running
    try:
        response = requests.get(f"{BRIDGE_URL}/health", timeout=3)
        if response.status_code != 200:
            print("❌ Bridge server is not running or not healthy")
            print("Start it with: ./start-bridge.sh dev")
            return False
    except:
        print("❌ Cannot connect to bridge server")
        print("Start it with: ./start-bridge.sh dev")
        return False
    
    # Run tests
    rest_success = test_bridge_direct()
    mcp_success = asyncio.run(test_mcp_tools())
    
    print("\\n" + "=" * 60)
    print("QUICK TEST RESULTS")
    print("=" * 60)
    print(f"REST API: {'PASSED' if rest_success else 'FAILED'}")
    print(f"MCP Tools: {'PASSED' if mcp_success else 'FAILED'}")
    
    overall = rest_success and mcp_success
    print(f"Overall: {'PASSED ✅' if overall else 'FAILED ❌'}")
    print("=" * 60)
    
    if overall:
        print("🎉 MCP Terminal Bridge is working perfectly!")
        print("   Ready to integrate with AI agents!")
    else:
        print("🔧 Some tests failed - check the output above")
    
    return overall

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)