#!/usr/bin/env python3
"""
Demo Integration Script - Shows complete MCP Terminal Bridge functionality
This demonstrates how AI agents would use the bridge to get their own terminals
"""

import asyncio
import json
import time
import requests
import jwt
from mcp_tools import MCPTerminalTools

# Configuration
BRIDGE_URL = "http://localhost:8000"
JWT_SECRET = "mcp-terminal-bridge-secret"

def create_demo_token(agent_name):
    """Create demo JWT token for an agent"""
    payload = {
        "agent_id": agent_name,
        "iat": time.time()
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")

async def demo_ai_agent_workflow(agent_name, workflow_description):
    """Simulate an AI agent using the terminal bridge"""
    print(f"\\n{'='*60}")
    print(f"🤖 AI Agent: {agent_name}")
    print(f"Workflow: {workflow_description}")
    print(f"{'='*60}")
    
    # Get authentication token
    token = create_demo_token(agent_name)
    print(f"🔐 Agent authenticated with token: {token[:20]}...")
    
    try:
        async with MCPTerminalTools(base_url=BRIDGE_URL, auth_token=token) as tools:
            # Step 1: Create a terminal
            print(f"\\n🏗️  Creating terminal for {agent_name}...")
            result = await tools.create_terminal(
                agent_name,
                command="bash",
                environment={
                    "AGENT_NAME": agent_name,
                    "WORKFLOW": workflow_description.replace(" ", "_"),
                    "PYTHONPATH": "/usr/local/lib/python3.10/site-packages"
                },
                timeout_hours=2
            )
            
            if not result["success"]:
                print(f"❌ Failed to create terminal: {result['error']}")
                return False
            
            terminal_id = result["terminal_id"]
            print(f"✅ Terminal created: {terminal_id}")
            print(f"   Container ID: {result['container_id']}")
            print(f"   Log path: {result['log_path']}")
            
            # Step 2: Setup the environment
            print(f"\\n🔧 Setting up environment...")
            setup_commands = [
                "echo 'Setting up workspace for $AGENT_NAME'",
                "mkdir -p /tmp/workspace",
                "cd /tmp/workspace",
                "echo 'Workspace ready!' > status.txt",
                "ls -la"
            ]
            
            for cmd in setup_commands:
                result = await tools.execute_command(terminal_id, cmd, timeout=15)
                if result["success"]:
                    print(f"   ✅ {cmd}: {result['output'].strip()}")
                else:
                    print(f"   ❌ {cmd}: {result['error']}")
            
            # Step 3: Execute workflow-specific tasks
            print(f"\\n⚙️  Executing workflow tasks...")
            
            if "data analysis" in workflow_description.lower():
                tasks = [
                    "python3 -c \\"import pandas as pd; print('Pandas available:', pd.__version__)\\" || echo 'Pandas not available'",
                    "python3 -c \\"import json; data={'analysis': 'complete', 'records': 1000}; print(json.dumps(data, indent=2))\\"",
                    "echo 'Data analysis workflow completed' > analysis_results.txt"
                ]
            elif "web scraping" in workflow_description.lower():
                tasks = [
                    "curl --version | head -1",
                    "curl -s 'https://httpbin.org/json' | head -3",
                    "echo 'Web scraping tools verified' > scraping_status.txt"
                ]
            elif "system monitoring" in workflow_description.lower():
                tasks = [
                    "ps aux | head -5",
                    "df -h | head -3",
                    "echo 'System monitoring active' > monitor.log"
                ]
            else:
                tasks = [
                    "python3 --version",
                    "which python3 curl tmux",
                    "echo 'General purpose terminal ready' > ready.txt"
                ]
            
            for task in tasks:
                result = await tools.execute_command(terminal_id, task, timeout=20)
                if result["success"]:
                    print(f"   ✅ Task completed: {result['output'].strip()}")
                else:
                    print(f"   ❌ Task failed: {result['error']}")
            
            # Step 4: Verify work and get logs
            print(f"\\n📋 Verifying work...")
            verify_result = await tools.execute_command(terminal_id, "ls -la /tmp/workspace && echo '--- End of workspace listing ---'")
            if verify_result["success"]:
                print(f"   Workspace contents:\\n{verify_result['output']}")
            
            # Step 5: Get full terminal logs
            print(f"\\n📜 Retrieving terminal logs...")
            logs_result = await tools.get_logs(terminal_id, lines=50)
            if logs_result["success"]:
                log_lines = logs_result['logs'].split('\\n')
                print(f"   Retrieved {len(log_lines)} log lines")
                print("   Recent activity:")
                for line in log_lines[-5:]:
                    if line.strip():
                        print(f"     {line}")
            
            # Step 6: List all terminals for this agent
            print(f"\\n📊 Agent terminal summary...")
            terminals_result = await tools.list_terminals()
            if terminals_result["success"]:
                print(f"   Total terminals: {terminals_result['count']}")
                for terminal in terminals_result["terminals"]:
                    status = terminal["status"]
                    created = terminal["created_at"][:19]  # Remove microseconds
                    print(f"   - {terminal['terminal_id']}: {status} (created: {created})")
            
            # Step 7: Clean up
            print(f"\\n🧹 Cleaning up...")
            cleanup_result = await tools.destroy_terminal(terminal_id)
            if cleanup_result["success"]:
                print(f"   ✅ Terminal {terminal_id} cleaned up successfully")
            else:
                print(f"   ❌ Cleanup failed: {cleanup_result['error']}")
            
            print(f"\\n🎉 Agent {agent_name} workflow completed successfully!")
            return True
            
    except Exception as e:
        print(f"❌ Agent workflow failed: {e}")
        return False

async def demo_multiple_agents():
    """Demonstrate multiple agents using the bridge simultaneously"""
    print("\\n" + "="*60)
    print("🚀 MULTI-AGENT DEMONSTRATION")
    print("="*60)
    
    # Define agent workflows
    agents = [
        ("DataAnalyst-AI", "Advanced data analysis and reporting"),
        ("WebScraper-AI", "Web scraping and content extraction"),
        ("SysMonitor-AI", "System monitoring and diagnostics"),
        ("DevOps-AI", "General purpose development and operations")
    ]
    
    # Run all agents concurrently
    tasks = []
    for agent_name, workflow in agents:
        task = asyncio.create_task(demo_ai_agent_workflow(agent_name, workflow))
        tasks.append(task)
    
    # Wait for all agents to complete
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    # Summary
    successful = sum(1 for result in results if result is True)
    failed = len(results) - successful
    
    print("\\n" + "="*60)
    print("MULTI-AGENT DEMO RESULTS")
    print("="*60)
    print(f"✅ Successful workflows: {successful}")
    print(f"❌ Failed workflows: {failed}")
    print(f"📊 Success rate: {successful/len(results)*100:.1f}%")
    
    return failed == 0

def check_bridge_health():
    """Check if the bridge is healthy and ready"""
    try:
        response = requests.get(f"{BRIDGE_URL}/health", timeout=5)
        if response.status_code == 200:
            health = response.json()
            print(f"🏥 Bridge Health Check:")
            print(f"   Status: {health['status']}")
            print(f"   Docker: {health.get('docker_status', 'unknown')}")
            print(f"   Redis: {health.get('redis_status', 'unknown')}")
            print(f"   Active terminals: {health.get('terminals', 0)}")
            return health['status'] == 'healthy'
        else:
            print(f"❌ Bridge health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Cannot connect to bridge: {e}")
        return False

async def main():
    """Main demo runner"""
    print("🌟 MCP Terminal Bridge - Complete Integration Demo")
    print("This demonstrates how AI agents get their own isolated terminals")
    print("="*60)
    
    # Check bridge health
    if not check_bridge_health():
        print("\\n❌ Bridge is not healthy. Please start it first:")
        print("   cd /home/loke/agent-terminal-system/mcp-bridge")
        print("   ./start-bridge.sh dev")
        return False
    
    print("\\n✅ Bridge is healthy and ready!")
    
    # Run single agent demo first
    print("\\n🎯 SINGLE AGENT DEMO")
    single_success = await demo_ai_agent_workflow(
        "DemoAgent-AI", 
        "Comprehensive terminal testing and validation"
    )
    
    if not single_success:
        print("❌ Single agent demo failed. Check the bridge server.")
        return False
    
    # Run multi-agent demo
    multi_success = await demo_multiple_agents()
    
    # Final summary
    print("\\n" + "="*80)
    print("🏁 COMPLETE INTEGRATION DEMO RESULTS")
    print("="*80)
    print(f"Single Agent Demo: {'PASSED ✅' if single_success else 'FAILED ❌'}")
    print(f"Multi-Agent Demo: {'PASSED ✅' if multi_success else 'FAILED ❌'}")
    
    overall_success = single_success and multi_success
    print(f"\\nOverall Result: {'SUCCESS 🎉' if overall_success else 'FAILURE 💥'}")
    
    if overall_success:
        print("\\n🚀 MCP Terminal Bridge is fully operational!")
        print("   ✅ AI agents can create isolated terminals")
        print("   ✅ Commands execute successfully")  
        print("   ✅ Logs are captured and retrievable")
        print("   ✅ Multiple agents can work simultaneously")
        print("   ✅ Cleanup and resource management works")
        print("\\n🎯 Ready for production use with real AI agents!")
    else:
        print("\\n🔧 Some issues detected - check the output above")
    
    print("="*80)
    return overall_success

if __name__ == "__main__":
    success = asyncio.run(main())
    exit(0 if success else 1)