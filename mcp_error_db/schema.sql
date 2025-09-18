-- MCP Agent Error Logging Database Schema
-- Designed for deduplication, categorization, and resolution tracking

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Enum types for better data integrity
CREATE TYPE error_category AS ENUM ('network', 'resource', 'config', 'dependency', 'runtime', 'auth', 'unknown');
CREATE TYPE error_severity AS ENUM ('critical', 'high', 'medium', 'low', 'info');
CREATE TYPE agent_status AS ENUM ('active', 'inactive', 'error', 'deploying');
CREATE TYPE resolution_status AS ENUM ('pending', 'in_progress', 'resolved', 'failed', 'deferred');

-- Agents table - track all MCP agents
CREATE TABLE agents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    agent_type VARCHAR(50),
    deployment_status agent_status DEFAULT 'inactive',
    last_heartbeat TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Error fingerprints - for deduplication
CREATE TABLE error_fingerprints (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fingerprint_hash VARCHAR(64) NOT NULL UNIQUE, -- SHA-256 hash
    error_type VARCHAR(100) NOT NULL,
    category error_category NOT NULL,
    error_pattern TEXT,
    first_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    occurrence_count INTEGER DEFAULT 1,
    resolution_count INTEGER DEFAULT 0,
    avg_resolution_time INTERVAL,
    is_known_issue BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Individual error instances
CREATE TABLE error_instances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fingerprint_id UUID NOT NULL REFERENCES error_fingerprints(id),
    agent_id UUID NOT NULL REFERENCES agents(id),
    severity error_severity NOT NULL,
    message TEXT NOT NULL,
    stack_trace TEXT,
    context JSONB DEFAULT '{}', -- Environment, config, etc.
    source_location VARCHAR(200), -- File:line or component
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolution_time INTERVAL GENERATED ALWAYS AS (resolved_at - timestamp) STORED
);

-- Resolution attempts and solutions
CREATE TABLE resolutions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fingerprint_id UUID NOT NULL REFERENCES error_fingerprints(id),
    attempted_by UUID REFERENCES agents(id), -- NULL if manual/external
    status resolution_status NOT NULL DEFAULT 'pending',
    solution_type VARCHAR(50), -- 'automated', 'manual', 'rollback', 'config_fix'
    solution_description TEXT,
    solution_steps JSONB, -- Structured steps for automation
    success_rate DECIMAL(5,2), -- Percentage success rate
    average_fix_time INTERVAL,
    attempts_count INTEGER DEFAULT 1,
    last_attempted TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Error patterns for learning
CREATE TABLE error_patterns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pattern_name VARCHAR(100) NOT NULL,
    pattern_regex TEXT,
    category error_category NOT NULL,
    detection_confidence DECIMAL(5,2) DEFAULT 0.0,
    auto_resolution_id UUID REFERENCES resolutions(id),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- System metrics for monitoring
CREATE TABLE system_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id UUID REFERENCES agents(id),
    metric_type VARCHAR(50) NOT NULL, -- 'cpu', 'memory', 'errors_per_hour', etc.
    metric_value DECIMAL(10,2) NOT NULL,
    unit VARCHAR(20),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_error_fingerprints_hash ON error_fingerprints(fingerprint_hash);
CREATE INDEX idx_error_fingerprints_category ON error_fingerprints(category);
CREATE INDEX idx_error_fingerprints_last_seen ON error_fingerprints(last_seen DESC);

CREATE INDEX idx_error_instances_fingerprint ON error_instances(fingerprint_id);
CREATE INDEX idx_error_instances_agent ON error_instances(agent_id);
CREATE INDEX idx_error_instances_timestamp ON error_instances(timestamp DESC);
CREATE INDEX idx_error_instances_severity ON error_instances(severity);

CREATE INDEX idx_resolutions_fingerprint ON resolutions(fingerprint_id);
CREATE INDEX idx_resolutions_status ON resolutions(status);
CREATE INDEX idx_resolutions_success_rate ON resolutions(success_rate DESC);

CREATE INDEX idx_agents_status ON agents(deployment_status);
CREATE INDEX idx_agents_heartbeat ON agents(last_heartbeat DESC);

CREATE INDEX idx_system_metrics_agent_type ON system_metrics(agent_id, metric_type);
CREATE INDEX idx_system_metrics_timestamp ON system_metrics(timestamp DESC);

-- Full-text search on error messages
CREATE INDEX idx_error_instances_message_fts ON error_instances USING gin(to_tsvector('english', message));

-- Triggers for automatic updates
CREATE OR REPLACE FUNCTION update_error_fingerprint_stats()
RETURNS TRIGGER AS $$
BEGIN
    -- Update fingerprint statistics when new error instance is added
    UPDATE error_fingerprints
    SET
        last_seen = NEW.timestamp,
        occurrence_count = occurrence_count + 1
    WHERE id = NEW.fingerprint_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_fingerprint_stats
    AFTER INSERT ON error_instances
    FOR EACH ROW
    EXECUTE FUNCTION update_error_fingerprint_stats();

CREATE OR REPLACE FUNCTION update_resolution_stats()
RETURNS TRIGGER AS $$
BEGIN
    -- Update resolution count when error is resolved
    IF NEW.resolved_at IS NOT NULL AND OLD.resolved_at IS NULL THEN
        UPDATE error_fingerprints
        SET
            resolution_count = resolution_count + 1,
            avg_resolution_time = (
                SELECT AVG(resolution_time)
                FROM error_instances
                WHERE fingerprint_id = NEW.fingerprint_id
                AND resolved_at IS NOT NULL
            )
        WHERE id = NEW.fingerprint_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_resolution_stats
    AFTER UPDATE ON error_instances
    FOR EACH ROW
    EXECUTE FUNCTION update_resolution_stats();

-- Function to generate error fingerprint
CREATE OR REPLACE FUNCTION generate_error_fingerprint(
    p_error_type VARCHAR(100),
    p_message TEXT,
    p_source_location VARCHAR(200)
) RETURNS VARCHAR(64) AS $$
BEGIN
    RETURN encode(
        digest(
            p_error_type || '::' ||
            regexp_replace(p_message, '\d+', 'N', 'g') || '::' ||
            COALESCE(p_source_location, ''),
            'sha256'
        ),
        'hex'
    );
END;
$$ LANGUAGE plpgsql;

-- Views for common queries
CREATE VIEW agent_error_summary AS
SELECT
    a.name as agent_name,
    a.deployment_status,
    COUNT(ei.id) as total_errors,
    COUNT(CASE WHEN ei.severity IN ('critical', 'high') THEN 1 END) as critical_errors,
    COUNT(CASE WHEN ei.resolved_at IS NOT NULL THEN 1 END) as resolved_errors,
    MAX(ei.timestamp) as last_error,
    AVG(EXTRACT(EPOCH FROM ei.resolution_time)) as avg_resolution_seconds
FROM agents a
LEFT JOIN error_instances ei ON a.id = ei.agent_id
WHERE ei.timestamp > NOW() - INTERVAL '24 hours'
GROUP BY a.id, a.name, a.deployment_status;

CREATE VIEW top_error_patterns AS
SELECT
    ef.error_type,
    ef.category,
    ef.occurrence_count,
    ef.resolution_count,
    ROUND((ef.resolution_count::DECIMAL / ef.occurrence_count) * 100, 2) as resolution_rate,
    ef.avg_resolution_time,
    ef.last_seen
FROM error_fingerprints ef
WHERE ef.occurrence_count > 1
ORDER BY ef.occurrence_count DESC, ef.last_seen DESC;

-- Initial data
INSERT INTO agents (name, agent_type, deployment_status) VALUES
('orchestrator', 'coordinator', 'inactive'),
('mcp-agent-1', 'worker', 'inactive'),
('mcp-agent-2', 'worker', 'inactive'),
('mcp-agent-3', 'worker', 'inactive');