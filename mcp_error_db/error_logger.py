#!/usr/bin/env python3
"""
MCP Agent Error Logging System
Provides error logging, deduplication, and resolution tracking for MCP deployment pipeline.
"""

import asyncio
import hashlib
import json
import logging
import sys
from datetime import datetime, timezone
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass
from enum import Enum

import asyncpg
import structlog

# Configure structured logging
structlog.configure(
    processors=[
        structlog.processors.add_log_level,
        structlog.processors.StackInfoRenderer(),
        structlog.dev.set_exc_info,
        structlog.processors.JSONRenderer()
    ],
    wrapper_class=structlog.make_filtering_bound_logger(30),  # INFO level
    logger_factory=structlog.PrintLoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

class ErrorCategory(Enum):
    NETWORK = "network"
    RESOURCE = "resource"
    CONFIG = "config"
    DEPENDENCY = "dependency"
    RUNTIME = "runtime"
    AUTH = "auth"
    UNKNOWN = "unknown"

class ErrorSeverity(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFO = "info"

class AgentStatus(Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    ERROR = "error"
    DEPLOYING = "deploying"

@dataclass
class ErrorInstance:
    error_type: str
    message: str
    category: ErrorCategory
    severity: ErrorSeverity
    agent_name: str
    stack_trace: Optional[str] = None
    context: Optional[Dict[str, Any]] = None
    source_location: Optional[str] = None
    timestamp: Optional[datetime] = None

@dataclass
class Resolution:
    solution_type: str
    solution_description: str
    solution_steps: Optional[Dict[str, Any]] = None
    attempted_by: Optional[str] = None

class MCPErrorLogger:
    """Main error logging and management system for MCP agents."""

    def __init__(self, db_url: str):
        self.db_url = db_url
        self.pool: Optional[asyncpg.Pool] = None

    async def initialize(self):
        """Initialize database connection pool."""
        try:
            self.pool = await asyncpg.create_pool(
                self.db_url,
                min_size=2,
                max_size=10,
                command_timeout=60
            )
            await logger.ainfo("Database connection pool initialized")
        except Exception as e:
            await logger.aerror("Failed to initialize database", error=str(e))
            raise

    async def close(self):
        """Close database connections."""
        if self.pool:
            await self.pool.close()
            await logger.ainfo("Database connections closed")

    def _generate_fingerprint(self, error_type: str, message: str, source_location: Optional[str] = None) -> str:
        """Generate unique fingerprint for error deduplication."""
        # Normalize message by replacing numbers with 'N' for better grouping
        normalized_message = message
        for char in '0123456789':
            normalized_message = normalized_message.replace(char, 'N')

        # Create fingerprint from type, normalized message, and location
        fingerprint_data = f"{error_type}::{normalized_message}::{source_location or ''}"
        return hashlib.sha256(fingerprint_data.encode()).hexdigest()

    async def register_agent(self, agent_name: str, agent_type: str = "worker") -> str:
        """Register or update an agent in the system."""
        async with self.pool.acquire() as conn:
            try:
                agent_id = await conn.fetchval("""
                    INSERT INTO agents (name, agent_type, deployment_status, last_heartbeat)
                    VALUES ($1, $2, $3, NOW())
                    ON CONFLICT (name)
                    DO UPDATE SET
                        last_heartbeat = NOW(),
                        updated_at = NOW()
                    RETURNING id
                """, agent_name, agent_type, AgentStatus.ACTIVE.value)

                await logger.ainfo("Agent registered", agent_name=agent_name, agent_id=str(agent_id))
                return str(agent_id)

            except Exception as e:
                await logger.aerror("Failed to register agent", agent_name=agent_name, error=str(e))
                raise

    async def log_error(self, error: ErrorInstance) -> str:
        """Log an error with automatic deduplication."""
        if error.timestamp is None:
            error.timestamp = datetime.now(timezone.utc)

        fingerprint = self._generate_fingerprint(
            error.error_type, error.message, error.source_location
        )

        async with self.pool.acquire() as conn:
            try:
                # Get or create agent
                agent_id = await conn.fetchval(
                    "SELECT id FROM agents WHERE name = $1", error.agent_name
                )
                if not agent_id:
                    agent_id = await self.register_agent(error.agent_name)

                # Get or create error fingerprint
                fingerprint_id = await conn.fetchval("""
                    INSERT INTO error_fingerprints (
                        fingerprint_hash, error_type, category, error_pattern, first_seen, last_seen
                    )
                    VALUES ($1, $2, $3, $4, $5, $5)
                    ON CONFLICT (fingerprint_hash)
                    DO UPDATE SET
                        last_seen = $5,
                        occurrence_count = error_fingerprints.occurrence_count + 1
                    RETURNING id
                """, fingerprint, error.error_type, error.category.value,
                    error.message[:500], error.timestamp)

                # Create error instance
                instance_id = await conn.fetchval("""
                    INSERT INTO error_instances (
                        fingerprint_id, agent_id, severity, message, stack_trace,
                        context, source_location, timestamp
                    )
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    RETURNING id
                """, fingerprint_id, agent_id, error.severity.value, error.message,
                    error.stack_trace, json.dumps(error.context or {}),
                    error.source_location, error.timestamp)

                await logger.ainfo(
                    "Error logged",
                    instance_id=str(instance_id),
                    fingerprint=fingerprint[:8],
                    agent=error.agent_name,
                    category=error.category.value,
                    severity=error.severity.value
                )

                return str(instance_id)

            except Exception as e:
                await logger.aerror("Failed to log error", error=str(e))
                raise

    async def resolve_error(self, instance_id: str, resolution: Resolution) -> bool:
        """Mark an error instance as resolved with solution details."""
        async with self.pool.acquire() as conn:
            try:
                # Get agent ID if provided
                attempted_by_id = None
                if resolution.attempted_by:
                    attempted_by_id = await conn.fetchval(
                        "SELECT id FROM agents WHERE name = $1", resolution.attempted_by
                    )

                # Get fingerprint for this instance
                fingerprint_id = await conn.fetchval("""
                    SELECT fingerprint_id FROM error_instances WHERE id = $1
                """, instance_id)

                if not fingerprint_id:
                    await logger.awarning("Error instance not found", instance_id=instance_id)
                    return False

                # Add resolution record
                resolution_id = await conn.fetchval("""
                    INSERT INTO resolutions (
                        fingerprint_id, attempted_by, status, solution_type,
                        solution_description, solution_steps
                    )
                    VALUES ($1, $2, 'resolved', $3, $4, $5)
                    RETURNING id
                """, fingerprint_id, attempted_by_id, resolution.solution_type,
                    resolution.solution_description, json.dumps(resolution.solution_steps or {}))

                # Mark instance as resolved
                await conn.execute("""
                    UPDATE error_instances
                    SET resolved_at = NOW()
                    WHERE id = $1
                """, instance_id)

                await logger.ainfo(
                    "Error resolved",
                    instance_id=instance_id,
                    resolution_id=str(resolution_id),
                    solution_type=resolution.solution_type
                )

                return True

            except Exception as e:
                await logger.aerror("Failed to resolve error", instance_id=instance_id, error=str(e))
                raise

    async def get_agent_errors(self, agent_name: str, hours: int = 24) -> List[Dict[str, Any]]:
        """Get recent errors for a specific agent."""
        async with self.pool.acquire() as conn:
            try:
                rows = await conn.fetch("""
                    SELECT
                        ei.id,
                        ei.message,
                        ei.severity,
                        ei.timestamp,
                        ei.resolved_at,
                        ef.error_type,
                        ef.category,
                        ef.occurrence_count
                    FROM error_instances ei
                    JOIN error_fingerprints ef ON ei.fingerprint_id = ef.id
                    JOIN agents a ON ei.agent_id = a.id
                    WHERE a.name = $1
                    AND ei.timestamp > NOW() - INTERVAL '%s hours'
                    ORDER BY ei.timestamp DESC
                """ % hours, agent_name)

                return [dict(row) for row in rows]

            except Exception as e:
                await logger.aerror("Failed to get agent errors", agent_name=agent_name, error=str(e))
                raise

    async def get_top_errors(self, limit: int = 10) -> List[Dict[str, Any]]:
        """Get most common unresolved errors."""
        async with self.pool.acquire() as conn:
            try:
                rows = await conn.fetch("""
                    SELECT
                        ef.error_type,
                        ef.category,
                        ef.occurrence_count,
                        ef.resolution_count,
                        ROUND((ef.resolution_count::DECIMAL / ef.occurrence_count) * 100, 2) as resolution_rate,
                        ef.last_seen,
                        ef.avg_resolution_time
                    FROM error_fingerprints ef
                    WHERE ef.occurrence_count > 1
                    ORDER BY
                        (ef.occurrence_count - ef.resolution_count) DESC,
                        ef.last_seen DESC
                    LIMIT $1
                """, limit)

                return [dict(row) for row in rows]

            except Exception as e:
                await logger.aerror("Failed to get top errors", error=str(e))
                raise

    async def get_system_health(self) -> Dict[str, Any]:
        """Get overall system health metrics."""
        async with self.pool.acquire() as conn:
            try:
                # Get basic stats
                stats = await conn.fetchrow("""
                    SELECT
                        COUNT(DISTINCT a.id) as total_agents,
                        COUNT(CASE WHEN a.deployment_status = 'active' THEN 1 END) as active_agents,
                        COUNT(ei.id) as total_errors_24h,
                        COUNT(CASE WHEN ei.severity IN ('critical', 'high') THEN 1 END) as critical_errors_24h,
                        COUNT(CASE WHEN ei.resolved_at IS NOT NULL THEN 1 END) as resolved_errors_24h
                    FROM agents a
                    LEFT JOIN error_instances ei ON a.id = ei.agent_id
                        AND ei.timestamp > NOW() - INTERVAL '24 hours'
                """)

                # Get error trend
                trend = await conn.fetch("""
                    SELECT
                        DATE_TRUNC('hour', timestamp) as hour,
                        COUNT(*) as error_count
                    FROM error_instances
                    WHERE timestamp > NOW() - INTERVAL '24 hours'
                    GROUP BY hour
                    ORDER BY hour
                """)

                return {
                    "summary": dict(stats),
                    "error_trend": [{"hour": row["hour"], "count": row["error_count"]} for row in trend]
                }

            except Exception as e:
                await logger.aerror("Failed to get system health", error=str(e))
                raise

# CLI interface for testing and management
async def main():
    """CLI interface for error logger testing."""
    import argparse

    parser = argparse.ArgumentParser(description="MCP Error Logger CLI")
    parser.add_argument("--db-url", required=True, help="PostgreSQL connection URL")
    parser.add_argument("--action", choices=["test", "health", "errors"], default="test")
    parser.add_argument("--agent", help="Agent name for testing")

    args = parser.parse_args()

    logger_instance = MCPErrorLogger(args.db_url)

    try:
        await logger_instance.initialize()

        if args.action == "test":
            # Test error logging
            test_agent = args.agent or "test-agent"

            await logger_instance.register_agent(test_agent, "test")

            test_error = ErrorInstance(
                error_type="ConnectionError",
                message="Failed to connect to MCP server on port 3000",
                category=ErrorCategory.NETWORK,
                severity=ErrorSeverity.HIGH,
                agent_name=test_agent,
                context={"port": 3000, "timeout": 30}
            )

            instance_id = await logger_instance.log_error(test_error)
            print(f"Logged test error: {instance_id}")

            # Test resolution
            resolution = Resolution(
                solution_type="config_fix",
                solution_description="Updated port configuration to 3001",
                solution_steps={"port": 3001, "restart_required": True},
                attempted_by=test_agent
            )

            success = await logger_instance.resolve_error(instance_id, resolution)
            print(f"Resolution {'successful' if success else 'failed'}")

        elif args.action == "health":
            health = await logger_instance.get_system_health()
            print(json.dumps(health, indent=2, default=str))

        elif args.action == "errors":
            errors = await logger_instance.get_top_errors()
            print(json.dumps(errors, indent=2, default=str))

    finally:
        await logger_instance.close()

if __name__ == "__main__":
    asyncio.run(main())