#!/usr/bin/env python3
"""
Setup script for MCP Error Logging Database
Creates database, applies schema, and validates installation.
"""

import asyncio
import os
import sys
from pathlib import Path

import asyncpg
import structlog

logger = structlog.get_logger()

class DatabaseSetup:
    """Handle database creation and schema application."""

    def __init__(self, admin_url: str, db_name: str = "mcp_errors"):
        self.admin_url = admin_url
        self.db_name = db_name
        self.db_url = self._build_db_url()

    def _build_db_url(self) -> str:
        """Build database URL for the specific database."""
        if self.admin_url.endswith('/'):
            base_url = self.admin_url[:-1]
        else:
            base_url = self.admin_url

        # Replace database name in URL
        if base_url.endswith('/postgres'):
            return base_url.replace('/postgres', f'/{self.db_name}')
        else:
            return f"{base_url}/{self.db_name}"

    async def create_database(self):
        """Create the database if it doesn't exist."""
        try:
            # Connect to default database to create new one
            conn = await asyncpg.connect(self.admin_url)

            # Check if database exists
            exists = await conn.fetchval(
                "SELECT 1 FROM pg_database WHERE datname = $1", self.db_name
            )

            if not exists:
                # Create database
                await conn.execute(f'CREATE DATABASE "{self.db_name}"')
                await logger.ainfo("Database created", database=self.db_name)
            else:
                await logger.ainfo("Database already exists", database=self.db_name)

            await conn.close()

        except Exception as e:
            await logger.aerror("Failed to create database", error=str(e))
            raise

    async def apply_schema(self):
        """Apply database schema from schema.sql file."""
        try:
            schema_path = Path(__file__).parent / "schema.sql"
            if not schema_path.exists():
                raise FileNotFoundError(f"Schema file not found: {schema_path}")

            # Read schema file
            with open(schema_path, 'r') as f:
                schema_sql = f.read()

            # Connect to the MCP errors database
            conn = await asyncpg.connect(self.db_url)

            # Execute schema
            await conn.execute(schema_sql)
            await logger.ainfo("Schema applied successfully")

            await conn.close()

        except Exception as e:
            await logger.aerror("Failed to apply schema", error=str(e))
            raise

    async def validate_installation(self):
        """Validate that the database is properly set up."""
        try:
            conn = await asyncpg.connect(self.db_url)

            # Check that key tables exist
            tables = await conn.fetch("""
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                AND table_type = 'BASE TABLE'
            """)

            table_names = {row['table_name'] for row in tables}
            expected_tables = {
                'agents', 'error_fingerprints', 'error_instances',
                'resolutions', 'error_patterns', 'system_metrics'
            }

            missing_tables = expected_tables - table_names
            if missing_tables:
                raise ValueError(f"Missing tables: {missing_tables}")

            # Test basic operations
            agent_count = await conn.fetchval("SELECT COUNT(*) FROM agents")
            await logger.ainfo("Validation successful", initial_agents=agent_count)

            await conn.close()
            return True

        except Exception as e:
            await logger.aerror("Validation failed", error=str(e))
            raise

    async def setup(self):
        """Complete setup process."""
        await logger.ainfo("Starting MCP Error Database setup")

        await self.create_database()
        await self.apply_schema()
        await self.validate_installation()

        await logger.ainfo(
            "Setup completed successfully",
            database_url=self.db_url.replace(self.db_url.split('@')[0].split('//')[1], '***')
        )

        return self.db_url

async def main():
    """CLI setup interface."""
    import argparse

    parser = argparse.ArgumentParser(description="Setup MCP Error Logging Database")
    parser.add_argument(
        "--admin-url",
        default=os.environ.get("POSTGRES_ADMIN_URL", "postgresql://postgres:password@localhost:5432/postgres"),
        help="PostgreSQL admin connection URL"
    )
    parser.add_argument(
        "--db-name",
        default="mcp_errors",
        help="Name for the MCP errors database"
    )
    parser.add_argument(
        "--output-config",
        help="File to write database connection configuration"
    )

    args = parser.parse_args()

    setup = DatabaseSetup(args.admin_url, args.db_name)

    try:
        db_url = await setup.setup()

        if args.output_config:
            config = {
                "database_url": db_url,
                "database_name": args.db_name,
                "created_at": str(asyncio.get_event_loop().time())
            }

            import json
            with open(args.output_config, 'w') as f:
                json.dump(config, f, indent=2)

            print(f"Configuration written to: {args.output_config}")

        print(f"Database URL: {db_url}")

    except Exception as e:
        print(f"Setup failed: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())