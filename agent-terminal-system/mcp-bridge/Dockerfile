FROM python:3.11-slim

LABEL maintainer="MCP Terminal Bridge"
LABEL description="MCP-compatible bridge for agent terminal management"

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY server.py .
COPY mcp_tools.py .
COPY mcp_server.py .
COPY config/ ./config/

# Create directories
RUN mkdir -p /app/logs /app/config

# Create non-root user for security
RUN useradd -r -s /bin/false mcpbridge && \
    chown -R mcpbridge:mcpbridge /app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Expose port
EXPOSE 8000

# Switch to non-root user
USER mcpbridge

# Start the server
CMD ["python", "server.py"]