# MCP Agent Error Logging Database

A scalable error logging and resolution tracking system designed for Multi-Agent MCP deployment pipelines.

## Features

- **Error Deduplication**: Automatic fingerprinting prevents duplicate error storage
- **Categorization**: Classify errors by type (network, resource, config, dependency, runtime, auth)
- **Resolution Tracking**: Track attempted fixes and successful solutions
- **Agent Management**: Monitor multiple MCP agents and their deployment status
- **Pattern Recognition**: Build knowledge base of common errors and solutions
- **Scalable Design**: PostgreSQL backend with async Python API

## Quick Start

### 1. Setup Database

```bash
# Install dependencies
pip install -r requirements.txt

# Setup database (requires PostgreSQL)
python setup.py --admin-url "postgresql://user:pass@localhost:5432/postgres"
```

### 2. Test Installation

```bash
# Test error logging
python error_logger.py --db-url "postgresql://user:pass@localhost:5432/mcp_errors" --action test --agent test-agent

# Check system health
python error_logger.py --db-url "postgresql://user:pass@localhost:5432/mcp_errors" --action health
```

## Database Schema

### Core Tables

- **agents**: Track MCP agent instances and status
- **error_fingerprints**: Deduplicated error patterns with occurrence counts
- **error_instances**: Individual error occurrences with full context
- **resolutions**: Solution attempts and success tracking
- **error_patterns**: Learned patterns for automated detection
- **system_metrics**: Performance and health monitoring

### Key Features

- Automatic error fingerprinting using SHA-256 hashing
- Trigger-based statistics updates for performance
- Full-text search on error messages
- Time-based partitioning ready
- Comprehensive indexing for fast queries

## API Usage

### Error Logging

```python
from error_logger import MCPErrorLogger, ErrorInstance, ErrorCategory, ErrorSeverity

logger = MCPErrorLogger("postgresql://user:pass@localhost:5432/mcp_errors")
await logger.initialize()

# Register agent
agent_id = await logger.register_agent("mcp-agent-1", "worker")

# Log error
error = ErrorInstance(
    error_type="ConnectionError",
    message="Failed to connect to MCP server",
    category=ErrorCategory.NETWORK,
    severity=ErrorSeverity.HIGH,
    agent_name="mcp-agent-1",
    context={"port": 3000, "timeout": 30}
)

instance_id = await logger.log_error(error)
```

### Resolution Tracking

```python
from error_logger import Resolution

resolution = Resolution(
    solution_type="config_fix",
    solution_description="Updated port configuration",
    solution_steps={"port": 3001, "restart_required": True},
    attempted_by="mcp-agent-1"
)

success = await logger.resolve_error(instance_id, resolution)
```

### Monitoring

```python
# Get agent-specific errors
errors = await logger.get_agent_errors("mcp-agent-1", hours=24)

# Get most common errors
top_errors = await logger.get_top_errors(limit=10)

# System health overview
health = await logger.get_system_health()
```

## Error Categories

- **NETWORK**: Connection failures, timeouts, DNS issues
- **RESOURCE**: Memory, CPU, disk space limitations
- **CONFIG**: Configuration errors, missing settings
- **DEPENDENCY**: Missing packages, version conflicts
- **RUNTIME**: Code execution errors, exceptions
- **AUTH**: Authentication and authorization failures
- **UNKNOWN**: Uncategorized errors requiring investigation

## Environment Variables

```bash
# Database connection
POSTGRES_ADMIN_URL=postgresql://postgres:password@localhost:5432/postgres
MCP_ERRORS_DB_URL=postgresql://postgres:password@localhost:5432/mcp_errors

# Logging
LOG_LEVEL=INFO
STRUCTURED_LOGGING=true
```

## Integration with MCP Agents

The error logger is designed to integrate seamlessly with MCP deployment workflows:

1. **Agent Registration**: Each agent registers itself on startup
2. **Automatic Logging**: Errors are logged with full context and categorization
3. **Pattern Learning**: Common errors build into reusable solution knowledge
4. **Health Monitoring**: Agent status and system health tracked continuously
5. **Resolution Coordination**: Agents can share successful fix patterns

## Performance Considerations

- Uses connection pooling for high throughput
- Async operations for non-blocking error logging
- Indexed queries for fast error retrieval
- Automatic statistics updates via database triggers
- Memory-efficient fingerprinting algorithm

## Next Steps

This database forms the foundation for Phase 1 of the MCP deployment pipeline. Integration points include:

- Agent deployment scripts for automatic registration
- Error monitoring dashboards
- Automated resolution application
- Cross-agent learning mechanisms
- Rollback procedure coordination