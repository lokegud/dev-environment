#!/usr/bin/env python3
"""
Integration Tests for MCP Terminal Bridge
Tests the complete integration between MCP, bridge server, and agent terminals
"""

import asyncio
import json
import os
import pytest
import requests
import time
from typing import Dict, Any
import jwt

# Test configuration
BRIDGE_URL = "http://localhost:8000"
TEST_AGENT_ID = "test-agent-integration"
JWT_SECRET = "mcp-terminal-bridge-secret"

class TestIntegration:
    """Integration test suite"""
    
    def __init__(self):
        self.auth_token = None
        self.terminal_id = None
        
    def setup(self):
        """Setup test environment"""
        print("Setting up integration tests...")
        
        # Create auth token
        self.auth_token = self._create_test_token()
        print(f"Created test token: {self.auth_token[:20]}...")
        
    def _create_test_token(self) -> str:
        """Create a test JWT token"""
        payload = {
            "agent_id": TEST_AGENT_ID,
            "iat": time.time()
        }
        return jwt.encode(payload, JWT_SECRET, algorithm="HS256")
    
    def _make_request(self, method: str, endpoint: str, **kwargs) -> Dict[str, Any]:
        """Make authenticated request to bridge server"""
        headers = kwargs.get("headers", {})
        headers["Authorization"] = f"Bearer {self.auth_token}"
        kwargs["headers"] = headers
        
        url = f"{BRIDGE_URL}{endpoint}"
        response = getattr(requests, method.lower())(url, **kwargs)
        
        return {
            "status_code": response.status_code,
            "data": response.json() if response.content else None,
            "text": response.text
        }
    
    def test_health_check(self):
        """Test bridge server health"""
        print("\n1. Testing health check...")
        
        try:
            response = requests.get(f"{BRIDGE_URL}/health")
            assert response.status_code == 200
            
            health_data = response.json()
            assert health_data["status"] == "healthy"
            
            print("✓ Health check passed")
            return True
        except Exception as e:
            print(f"✗ Health check failed: {e}")
            return False
    
    def test_create_terminal(self):
        """Test terminal creation"""
        print("\n2. Testing terminal creation...")
        
        try:
            payload = {
                "agent_id": TEST_AGENT_ID,
                "command": "bash",
                "environment": {
                    "TEST_VAR": "integration_test"
                },
                "timeout_hours": 1
            }
            
            response = self._make_request("POST", "/terminals", json=payload)
            assert response["status_code"] == 200
            
            data = response["data"]
            assert data["agent_id"] == TEST_AGENT_ID
            assert data["status"] == "running"
            assert "terminal_id" in data
            
            self.terminal_id = data["terminal_id"]
            print(f"✓ Terminal created: {self.terminal_id}")
            return True
            
        except Exception as e:
            print(f"✗ Terminal creation failed: {e}")
            return False
    
    def test_execute_command(self):
        """Test command execution"""
        print("\n3. Testing command execution...")
        
        if not self.terminal_id:
            print("✗ No terminal available for testing")
            return False
        
        try:
            # Test basic command
            payload = {
                "command": "echo 'Hello from MCP Terminal!'",
                "timeout": 10
            }
            
            response = self._make_request("POST", f"/terminals/{self.terminal_id}/execute", json=payload)
            assert response["status_code"] == 200
            
            data = response["data"]
            assert data["exit_code"] == 0
            assert "Hello from MCP Terminal!" in data["output"]
            
            print("✓ Basic command execution successful")
            
            # Test environment variable
            payload = {
                "command": "echo $TEST_VAR",
                "timeout": 10
            }
            
            response = self._make_request("POST", f"/terminals/{self.terminal_id}/execute", json=payload)
            assert response["status_code"] == 200
            
            data = response["data"]
            assert data["exit_code"] == 0
            assert "integration_test" in data["output"]
            
            print("✓ Environment variable test successful")
            return True
            
        except Exception as e:
            print(f"✗ Command execution failed: {e}")
            return False
    
    def test_get_logs(self):
        """Test log retrieval"""
        print("\n4. Testing log retrieval...")
        
        if not self.terminal_id:
            print("✗ No terminal available for testing")
            return False
        
        try:
            response = self._make_request("GET", f"/terminals/{self.terminal_id}/logs?lines=50")
            assert response["status_code"] == 200
            
            data = response["data"]
            assert "logs" in data
            assert len(data["logs"]) > 0
            
            print("✓ Log retrieval successful")
            print(f"  Retrieved {len(data['logs'].split('\\n'))} lines")
            return True
            
        except Exception as e:
            print(f"✗ Log retrieval failed: {e}")
            return False
    
    def test_list_terminals(self):
        """Test terminal listing"""
        print("\n5. Testing terminal listing...")
        
        try:
            response = self._make_request("GET", "/terminals")
            assert response["status_code"] == 200
            
            data = response["data"]
            assert "terminals" in data
            assert len(data["terminals"]) > 0
            
            # Find our test terminal
            found_terminal = False
            for terminal in data["terminals"]:
                if terminal["terminal_id"] == self.terminal_id:
                    found_terminal = True
                    assert terminal["agent_id"] == TEST_AGENT_ID
                    break
            
            assert found_terminal, "Test terminal not found in list"
            
            print(f"✓ Terminal listing successful ({len(data['terminals'])} terminals)")
            return True
            
        except Exception as e:
            print(f"✗ Terminal listing failed: {e}")
            return False
    
    def test_authentication(self):
        """Test authentication and authorization"""
        print("\n6. Testing authentication...")
        
        try:
            # Test without token
            response = requests.get(f"{BRIDGE_URL}/terminals")
            assert response.status_code == 401
            
            print("✓ Unauthorized request properly rejected")
            
            # Test with invalid token
            headers = {"Authorization": "Bearer invalid-token"}
            response = requests.get(f"{BRIDGE_URL}/terminals", headers=headers)
            assert response.status_code == 401
            
            print("✓ Invalid token properly rejected")
            
            # Test with valid token (should work)
            response = self._make_request("GET", "/terminals")
            assert response["status_code"] == 200
            
            print("✓ Valid token accepted")
            return True
            
        except Exception as e:
            print(f"✗ Authentication test failed: {e}")
            return False
    
    def test_cleanup_terminal(self):
        """Test terminal cleanup"""
        print("\n7. Testing terminal cleanup...")
        
        if not self.terminal_id:
            print("✗ No terminal available for testing")
            return False
        
        try:
            response = self._make_request("DELETE", f"/terminals/{self.terminal_id}")
            assert response["status_code"] == 200
            
            data = response["data"]
            assert data["success"] == True
            
            print("✓ Terminal cleanup successful")
            
            # Verify terminal is no longer accessible
            response = self._make_request("GET", f"/terminals/{self.terminal_id}/logs")
            assert response["status_code"] == 404
            
            print("✓ Terminal properly removed")
            return True
            
        except Exception as e:
            print(f"✗ Terminal cleanup failed: {e}")
            return False
    
    def run_all_tests(self):
        """Run all integration tests"""
        print("=" * 60)
        print("MCP Terminal Bridge Integration Tests")
        print("=" * 60)
        
        self.setup()
        
        tests = [
            self.test_health_check,
            self.test_create_terminal,
            self.test_execute_command,
            self.test_get_logs,
            self.test_list_terminals,
            self.test_authentication,
            self.test_cleanup_terminal
        ]
        
        passed = 0
        failed = 0
        
        for test in tests:
            try:
                if test():
                    passed += 1
                else:
                    failed += 1
            except Exception as e:
                print(f"✗ {test.__name__} failed with exception: {e}")
                failed += 1
        
        print("\n" + "=" * 60)
        print(f"Integration Test Results: {passed} passed, {failed} failed")
        print("=" * 60)
        
        return failed == 0

async def test_mcp_tools():
    """Test MCP tools directly"""
    print("\n" + "=" * 60)
    print("Testing MCP Tools")
    print("=" * 60)
    
    # Import here to avoid issues if MCP not available
    try:
        from mcp_tools import MCPTerminalTools
    except ImportError:
        print("✗ MCP tools not available")
        return False
    
    # Create test token
    test_token = jwt.encode(
        {"agent_id": "mcp-test-agent", "iat": time.time()},
        JWT_SECRET,
        algorithm="HS256"
    )
    
    try:
        async with MCPTerminalTools(base_url=BRIDGE_URL, auth_token=test_token) as tools:
            # Test tools schema
            schema = tools.get_tools_schema()
            assert len(schema) > 0
            print(f"✓ Found {len(schema)} MCP tools")
            
            # Test create terminal
            result = await tools.create_terminal("mcp-test-agent")
            if not result["success"]:
                print(f"✗ Create terminal failed: {result['error']}")
                return False
            
            terminal_id = result["terminal_id"]
            print(f"✓ Created terminal: {terminal_id}")
            
            # Test execute command
            result = await tools.execute_command(terminal_id, "echo 'MCP test'")
            if not result["success"]:
                print(f"✗ Execute command failed: {result['error']}")
                return False
            
            assert "MCP test" in result["output"]
            print("✓ Command execution via MCP tools successful")
            
            # Test get logs
            result = await tools.get_logs(terminal_id)
            if not result["success"]:
                print(f"✗ Get logs failed: {result['error']}")
                return False
            
            print("✓ Log retrieval via MCP tools successful")
            
            # Cleanup
            result = await tools.destroy_terminal(terminal_id)
            if not result["success"]:
                print(f"✗ Cleanup failed: {result['error']}")
                return False
            
            print("✓ Terminal cleanup via MCP tools successful")
            
        print("✓ All MCP tools tests passed")
        return True
        
    except Exception as e:
        print(f"✗ MCP tools test failed: {e}")
        return False

def main():
    """Main test runner"""
    print("Starting MCP Terminal Bridge Integration Tests...")
    
    # Check if bridge server is running
    try:
        response = requests.get(f"{BRIDGE_URL}/health", timeout=5)
        if response.status_code != 200:
            print(f"Bridge server not healthy: {response.status_code}")
            return False
    except Exception as e:
        print(f"Cannot connect to bridge server at {BRIDGE_URL}: {e}")
        print("Please start the bridge server first:")
        print("  ./start-bridge.sh dev")
        return False
    
    # Run REST API tests
    test_integration = TestIntegration()
    rest_success = test_integration.run_all_tests()
    
    # Run MCP tools tests
    mcp_success = asyncio.run(test_mcp_tools())
    
    # Final results
    print("\n" + "=" * 60)
    print("FINAL RESULTS")
    print("=" * 60)
    print(f"REST API Tests: {'PASSED' if rest_success else 'FAILED'}")
    print(f"MCP Tools Tests: {'PASSED' if mcp_success else 'FAILED'}")
    
    overall_success = rest_success and mcp_success
    print(f"Overall: {'PASSED' if overall_success else 'FAILED'}")
    print("=" * 60)
    
    return overall_success

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)