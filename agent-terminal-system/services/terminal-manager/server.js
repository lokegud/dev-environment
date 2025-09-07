const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const Docker = require('dockerode');
const redis = require('redis');
const { Client: ElasticsearchClient } = require('@elastic/elasticsearch');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const winston = require('winston');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const socketIO = require('socket.io');
const pty = require('node-pty');

// Configuration
const config = {
    port: process.env.PORT || 3000,
    redisUrl: process.env.REDIS_URL || 'redis://localhost:6379',
    elasticsearchUrl: process.env.ELASTICSEARCH_URL || 'http://localhost:9200',
    jwtSecret: process.env.JWT_SECRET || 'your-secret-key',
    dockerSocket: process.env.DOCKER_SOCKET || '/var/run/docker.sock',
    logLevel: process.env.LOG_LEVEL || 'info'
};

// Logger setup
const logger = winston.createLogger({
    level: config.logLevel,
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.Console(),
        new winston.transports.File({ filename: 'terminal-manager.log' })
    ]
});

// Initialize services
const app = express();
const server = http.createServer(app);
const io = socketIO(server, {
    cors: {
        origin: '*',
        methods: ['GET', 'POST']
    }
});

const docker = new Docker({ socketPath: config.dockerSocket });
const redisClient = redis.createClient({ url: config.redisUrl });
const esClient = new ElasticsearchClient({ node: config.elasticsearchUrl });

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Rate limiting
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100 // limit each IP to 100 requests per windowMs
});
app.use('/api/', limiter);

// Terminal Manager Class
class TerminalManager {
    constructor() {
        this.terminals = new Map();
        this.agentProfiles = new Map();
    }

    async createTerminal(agentId, options = {}) {
        const terminalId = uuidv4();
        const containerName = `agent-terminal-${agentId}-${terminalId}`;
        
        try {
            // Create container with specific configuration
            const container = await docker.createContainer({
                Image: 'agent-terminal:latest',
                name: containerName,
                Hostname: `agent-${agentId}`,
                Env: [
                    `AGENT_ID=${agentId}`,
                    `AGENT_NAME=${options.agentName || agentId}`,
                    `TERMINAL_THEME=${options.theme || 'default'}`,
                    `ENABLE_RECORDING=${options.enableRecording || 'true'}`,
                    `LOG_COLLECTOR_URL=http://terminal-manager:3000/api/logs`
                ],
                HostConfig: {
                    Memory: options.memoryLimit || 512 * 1024 * 1024, // 512MB default
                    CpuShares: options.cpuShares || 512,
                    Binds: [
                        `agent-homes:/home/agent:rw`,
                        `agent-workspaces:/home/agent/workspace:rw`,
                        `${agentId}-ssh:/home/agent/.ssh:rw`,
                        `terminal-logs:/var/log/agent-terminal:rw`
                    ],
                    NetworkMode: 'agent-terminal-net',
                    RestartPolicy: {
                        Name: 'unless-stopped'
                    },
                    SecurityOpt: options.securityOpt || ['no-new-privileges'],
                    ReadonlyRootfs: false,
                    CapDrop: ['ALL'],
                    CapAdd: ['CHOWN', 'SETUID', 'SETGID', 'DAC_OVERRIDE']
                },
                Labels: {
                    'agent.id': agentId,
                    'terminal.id': terminalId,
                    'created.at': new Date().toISOString()
                },
                AttachStdin: true,
                AttachStdout: true,
                AttachStderr: true,
                Tty: true,
                OpenStdin: true,
                StdinOnce: false
            });

            await container.start();

            // Store terminal info in Redis
            await redisClient.hSet(`terminal:${terminalId}`, {
                agentId,
                containerId: container.id,
                containerName,
                status: 'running',
                createdAt: new Date().toISOString(),
                ...options
            });

            // Add to local cache
            this.terminals.set(terminalId, {
                id: terminalId,
                agentId,
                container,
                containerName,
                status: 'running'
            });

            // Log terminal creation
            await this.logEvent(agentId, 'terminal_created', {
                terminalId,
                containerName,
                options
            });

            logger.info(`Terminal created for agent ${agentId}`, { terminalId, containerName });
            
            return {
                terminalId,
                containerName,
                websocketUrl: `ws://localhost:${config.port}/terminals/${terminalId}`,
                httpUrl: `http://localhost:8080/terminal/${terminalId}`
            };
        } catch (error) {
            logger.error(`Failed to create terminal for agent ${agentId}`, error);
            throw error;
        }
    }

    async destroyTerminal(terminalId) {
        const terminal = this.terminals.get(terminalId);
        if (!terminal) {
            throw new Error(`Terminal ${terminalId} not found`);
        }

        try {
            const container = docker.getContainer(terminal.container.id);
            await container.stop();
            await container.remove();

            // Remove from Redis
            await redisClient.del(`terminal:${terminalId}`);

            // Remove from local cache
            this.terminals.delete(terminalId);

            // Log terminal destruction
            await this.logEvent(terminal.agentId, 'terminal_destroyed', { terminalId });

            logger.info(`Terminal destroyed`, { terminalId });
            return { success: true };
        } catch (error) {
            logger.error(`Failed to destroy terminal ${terminalId}`, error);
            throw error;
        }
    }

    async listTerminals(agentId = null) {
        try {
            const filters = agentId ? { label: [`agent.id=${agentId}`] } : {};
            const containers = await docker.listContainers({
                all: true,
                filters
            });

            return containers.map(container => ({
                terminalId: container.Labels['terminal.id'],
                agentId: container.Labels['agent.id'],
                containerName: container.Names[0].replace('/', ''),
                status: container.State,
                created: container.Created,
                ports: container.Ports
            }));
        } catch (error) {
            logger.error('Failed to list terminals', error);
            throw error;
        }
    }

    async getTerminalLogs(terminalId, options = {}) {
        const terminal = this.terminals.get(terminalId);
        if (!terminal) {
            throw new Error(`Terminal ${terminalId} not found`);
        }

        try {
            const container = docker.getContainer(terminal.container.id);
            const stream = await container.logs({
                stdout: true,
                stderr: true,
                follow: options.follow || false,
                tail: options.tail || 100,
                timestamps: true
            });

            return stream;
        } catch (error) {
            logger.error(`Failed to get logs for terminal ${terminalId}`, error);
            throw error;
        }
    }

    async executeCommand(terminalId, command) {
        const terminal = this.terminals.get(terminalId);
        if (!terminal) {
            throw new Error(`Terminal ${terminalId} not found`);
        }

        try {
            const container = docker.getContainer(terminal.container.id);
            const exec = await container.exec({
                Cmd: ['bash', '-c', command],
                AttachStdout: true,
                AttachStderr: true
            });

            const stream = await exec.start();
            return stream;
        } catch (error) {
            logger.error(`Failed to execute command in terminal ${terminalId}`, error);
            throw error;
        }
    }

    async resizeTerminal(terminalId, cols, rows) {
        const terminal = this.terminals.get(terminalId);
        if (!terminal) {
            throw new Error(`Terminal ${terminalId} not found`);
        }

        try {
            const container = docker.getContainer(terminal.container.id);
            await container.resize({ h: rows, w: cols });
            return { success: true };
        } catch (error) {
            logger.error(`Failed to resize terminal ${terminalId}`, error);
            throw error;
        }
    }

    async saveAgentProfile(agentId, profile) {
        try {
            await redisClient.hSet(`agent:profile:${agentId}`, profile);
            this.agentProfiles.set(agentId, profile);
            
            await this.logEvent(agentId, 'profile_updated', { profile });
            
            return { success: true };
        } catch (error) {
            logger.error(`Failed to save profile for agent ${agentId}`, error);
            throw error;
        }
    }

    async getAgentProfile(agentId) {
        try {
            let profile = this.agentProfiles.get(agentId);
            if (!profile) {
                profile = await redisClient.hGetAll(`agent:profile:${agentId}`);
                if (profile && Object.keys(profile).length > 0) {
                    this.agentProfiles.set(agentId, profile);
                }
            }
            return profile || {};
        } catch (error) {
            logger.error(`Failed to get profile for agent ${agentId}`, error);
            throw error;
        }
    }

    async logEvent(agentId, eventType, data) {
        try {
            await esClient.index({
                index: 'agent-terminal-events',
                body: {
                    timestamp: new Date().toISOString(),
                    agentId,
                    eventType,
                    data
                }
            });
        } catch (error) {
            logger.error('Failed to log event to Elasticsearch', error);
        }
    }
}

// Initialize Terminal Manager
const terminalManager = new TerminalManager();

// Authentication middleware
const authenticate = (req, res, next) => {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) {
        return res.status(401).json({ error: 'No token provided' });
    }

    try {
        const decoded = jwt.verify(token, config.jwtSecret);
        req.agentId = decoded.agentId;
        next();
    } catch (error) {
        return res.status(403).json({ error: 'Invalid token' });
    }
};

// REST API Routes
app.post('/api/terminals', authenticate, async (req, res) => {
    try {
        const result = await terminalManager.createTerminal(req.agentId, req.body);
        res.json(result);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.delete('/api/terminals/:terminalId', authenticate, async (req, res) => {
    try {
        const result = await terminalManager.destroyTerminal(req.params.terminalId);
        res.json(result);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/terminals', authenticate, async (req, res) => {
    try {
        const terminals = await terminalManager.listTerminals(req.agentId);
        res.json(terminals);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/terminals/:terminalId/logs', authenticate, async (req, res) => {
    try {
        const stream = await terminalManager.getTerminalLogs(req.params.terminalId, req.query);
        stream.pipe(res);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/terminals/:terminalId/execute', authenticate, async (req, res) => {
    try {
        const stream = await terminalManager.executeCommand(req.params.terminalId, req.body.command);
        stream.pipe(res);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/terminals/:terminalId/resize', authenticate, async (req, res) => {
    try {
        const result = await terminalManager.resizeTerminal(
            req.params.terminalId,
            req.body.cols,
            req.body.rows
        );
        res.json(result);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/agents/:agentId/profile', authenticate, async (req, res) => {
    try {
        const profile = await terminalManager.getAgentProfile(req.params.agentId);
        res.json(profile);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.put('/api/agents/:agentId/profile', authenticate, async (req, res) => {
    try {
        const result = await terminalManager.saveAgentProfile(req.params.agentId, req.body);
        res.json(result);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Log collection endpoint
app.post('/api/logs', express.text({ type: 'application/json' }), async (req, res) => {
    try {
        const agentId = req.headers['x-agent-id'];
        const logData = JSON.parse(req.body);
        
        await esClient.index({
            index: 'agent-terminal-logs',
            body: {
                ...logData,
                receivedAt: new Date().toISOString()
            }
        });
        
        res.status(200).send('OK');
    } catch (error) {
        logger.error('Failed to process log', error);
        res.status(500).send('Error');
    }
});

// WebSocket handling for terminal interaction
io.on('connection', (socket) => {
    logger.info('New WebSocket connection', { socketId: socket.id });

    socket.on('terminal:connect', async (data) => {
        const { terminalId, token } = data;
        
        try {
            // Verify token
            const decoded = jwt.verify(token, config.jwtSecret);
            
            // Get terminal info
            const terminal = terminalManager.terminals.get(terminalId);
            if (!terminal) {
                socket.emit('error', { message: 'Terminal not found' });
                return;
            }

            // Create PTY session
            const container = docker.getContainer(terminal.container.id);
            const exec = await container.exec({
                Cmd: ['/bin/bash'],
                AttachStdin: true,
                AttachStdout: true,
                AttachStderr: true,
                Tty: true
            });

            const stream = await exec.start({ hijack: true, stdin: true });

            // Pipe data between socket and container
            socket.on('terminal:input', (data) => {
                stream.write(data);
            });

            stream.on('data', (chunk) => {
                socket.emit('terminal:output', chunk.toString());
            });

            socket.on('terminal:resize', async (dimensions) => {
                await terminalManager.resizeTerminal(terminalId, dimensions.cols, dimensions.rows);
            });

            socket.on('disconnect', () => {
                stream.end();
                logger.info('WebSocket disconnected', { socketId: socket.id, terminalId });
            });

        } catch (error) {
            logger.error('WebSocket terminal connection failed', error);
            socket.emit('error', { message: error.message });
        }
    });
});

// Health check endpoint
app.get('/health', async (req, res) => {
    try {
        await redisClient.ping();
        await esClient.ping();
        res.json({ status: 'healthy', timestamp: new Date().toISOString() });
    } catch (error) {
        res.status(503).json({ status: 'unhealthy', error: error.message });
    }
});

// Initialize services
async function initialize() {
    try {
        await redisClient.connect();
        logger.info('Connected to Redis');

        // Build terminal image if needed
        try {
            await docker.buildImage({
                context: __dirname + '/../../docker',
                src: ['Dockerfile.agent-terminal', 'terminal-wrapper.sh', 'config/']
            }, { t: 'agent-terminal:latest' });
            logger.info('Terminal image built successfully');
        } catch (error) {
            logger.warn('Failed to build terminal image, assuming it exists', error);
        }

        server.listen(config.port, () => {
            logger.info(`Terminal Manager Service running on port ${config.port}`);
        });
    } catch (error) {
        logger.error('Failed to initialize Terminal Manager', error);
        process.exit(1);
    }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
    logger.info('SIGTERM received, shutting down gracefully');
    server.close();
    await redisClient.quit();
    process.exit(0);
});

// Start the service
initialize();