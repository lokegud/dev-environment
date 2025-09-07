const express = require('express');
const http = require('http');
const socketIO = require('socket.io');
const redis = require('redis');
const { Client: ElasticsearchClient } = require('@elastic/elasticsearch');
const chokidar = require('chokidar');
const { Tail } = require('tail');
const winston = require('winston');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

// Configuration
const config = {
    port: process.env.WS_PORT || 8081,
    redisUrl: process.env.REDIS_URL || 'redis://localhost:6379',
    elasticsearchUrl: process.env.ELASTICSEARCH_URL || 'http://localhost:9200',
    logDir: process.env.LOG_DIR || '/var/log/agent-terminal',
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
        new winston.transports.File({ filename: 'log-streamer.log' })
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

const redisClient = redis.createClient({ url: config.redisUrl });
const esClient = new ElasticsearchClient({ node: config.elasticsearchUrl });

// Middleware
app.use(cors());
app.use(express.json());

// Log Streaming Manager
class LogStreamManager {
    constructor() {
        this.watchers = new Map();
        this.tails = new Map();
        this.clients = new Map();
    }

    // Start watching log files for an agent
    startWatching(agentId) {
        if (this.watchers.has(agentId)) {
            logger.warn(`Already watching logs for agent ${agentId}`);
            return;
        }

        const agentLogPattern = path.join(config.logDir, `${agentId}-*.log`);
        const agentJsonlPattern = path.join(config.logDir, `${agentId}-*.jsonl`);
        
        // Watch for new log files
        const watcher = chokidar.watch([agentLogPattern, agentJsonlPattern], {
            ignored: /[\/\\]\./,
            persistent: true,
            ignoreInitial: false
        });

        watcher
            .on('add', (filePath) => {
                logger.info(`New log file detected: ${filePath}`);
                this.startTailing(agentId, filePath);
            })
            .on('change', (filePath) => {
                // File changed, ensure we're tailing it
                if (!this.tails.has(filePath)) {
                    this.startTailing(agentId, filePath);
                }
            })
            .on('unlink', (filePath) => {
                logger.info(`Log file removed: ${filePath}`);
                this.stopTailing(filePath);
            })
            .on('error', (error) => {
                logger.error(`Watcher error for agent ${agentId}:`, error);
            });

        this.watchers.set(agentId, watcher);
        logger.info(`Started watching logs for agent ${agentId}`);
    }

    // Stop watching log files for an agent
    stopWatching(agentId) {
        const watcher = this.watchers.get(agentId);
        if (watcher) {
            watcher.close();
            this.watchers.delete(agentId);
            
            // Stop all tails for this agent
            for (const [filePath, tail] of this.tails.entries()) {
                if (filePath.includes(agentId)) {
                    this.stopTailing(filePath);
                }
            }
            
            logger.info(`Stopped watching logs for agent ${agentId}`);
        }
    }

    // Start tailing a specific log file
    startTailing(agentId, filePath) {
        if (this.tails.has(filePath)) {
            return; // Already tailing this file
        }

        try {
            const tail = new Tail(filePath, { follow: true, fromBeginning: false });
            
            tail.on('line', (data) => {
                this.processLogLine(agentId, filePath, data);
            });

            tail.on('error', (error) => {
                logger.error(`Tail error for ${filePath}:`, error);
                this.stopTailing(filePath);
            });

            this.tails.set(filePath, tail);
            logger.info(`Started tailing ${filePath}`);
        } catch (error) {
            logger.error(`Failed to start tailing ${filePath}:`, error);
        }
    }

    // Stop tailing a specific log file
    stopTailing(filePath) {
        const tail = this.tails.get(filePath);
        if (tail) {
            tail.unwatch();
            this.tails.delete(filePath);
            logger.info(`Stopped tailing ${filePath}`);
        }
    }

    // Process a log line and stream to clients
    async processLogLine(agentId, filePath, data) {
        try {
            let logData;
            const fileName = path.basename(filePath);
            const timestamp = new Date().toISOString();

            // Try to parse as JSON (structured logs)
            try {
                logData = JSON.parse(data);
                logData.source_file = fileName;
                logData.streamed_at = timestamp;
            } catch {
                // Plain text log
                logData = {
                    timestamp,
                    agent_id: agentId,
                    source_file: fileName,
                    message: data,
                    log_type: 'plaintext',
                    streamed_at: timestamp
                };
            }

            // Stream to connected clients
            this.streamToClients(agentId, logData);

            // Index in Elasticsearch
            await this.indexLog(logData);

            // Cache recent logs in Redis
            await this.cacheLog(agentId, logData);

        } catch (error) {
            logger.error('Error processing log line:', error);
        }
    }

    // Stream log data to connected clients
    streamToClients(agentId, logData) {
        // Stream to clients watching this specific agent
        const agentRoom = `agent:${agentId}`;
        io.to(agentRoom).emit('log', logData);

        // Stream to clients watching all agents
        io.to('all-agents').emit('log', logData);
    }

    // Index log in Elasticsearch
    async indexLog(logData) {
        try {
            await esClient.index({
                index: `agent-terminal-logs-${new Date().toISOString().slice(0, 7)}`, // Monthly indices
                body: logData
            });
        } catch (error) {
            logger.error('Failed to index log in Elasticsearch:', error);
        }
    }

    // Cache recent logs in Redis
    async cacheLog(agentId, logData) {
        try {
            const key = `logs:recent:${agentId}`;
            await redisClient.lPush(key, JSON.stringify(logData));
            await redisClient.lTrim(key, 0, 1000); // Keep last 1000 logs
            await redisClient.expire(key, 3600); // Expire after 1 hour
        } catch (error) {
            logger.error('Failed to cache log in Redis:', error);
        }
    }

    // Get recent logs for an agent
    async getRecentLogs(agentId, limit = 100) {
        try {
            const key = `logs:recent:${agentId}`;
            const logs = await redisClient.lRange(key, 0, limit - 1);
            return logs.map(log => JSON.parse(log));
        } catch (error) {
            logger.error('Failed to get recent logs:', error);
            return [];
        }
    }

    // Search logs in Elasticsearch
    async searchLogs(query) {
        try {
            const response = await esClient.search({
                index: 'agent-terminal-logs-*',
                body: {
                    query: {
                        multi_match: {
                            query: query.q || '',
                            fields: ['message', 'data.*']
                        }
                    },
                    sort: [
                        { timestamp: { order: 'desc' } }
                    ],
                    size: query.size || 100,
                    from: query.from || 0
                }
            });

            return {
                total: response.body.hits.total.value,
                logs: response.body.hits.hits.map(hit => hit._source)
            };
        } catch (error) {
            logger.error('Failed to search logs:', error);
            throw error;
        }
    }
}

// Initialize Log Stream Manager
const logManager = new LogStreamManager();

// WebSocket connection handling
io.on('connection', (socket) => {
    logger.info('New log streaming connection', { socketId: socket.id });

    // Subscribe to agent logs
    socket.on('subscribe', async (data) => {
        const { agentId, includeRecent = true } = data;
        
        if (agentId === 'all') {
            socket.join('all-agents');
            logger.info('Client subscribed to all agent logs', { socketId: socket.id });
        } else {
            socket.join(`agent:${agentId}`);
            logManager.startWatching(agentId);
            
            // Send recent logs if requested
            if (includeRecent) {
                const recentLogs = await logManager.getRecentLogs(agentId);
                socket.emit('recent-logs', recentLogs);
            }
            
            logger.info('Client subscribed to agent logs', { socketId: socket.id, agentId });
        }
    });

    // Unsubscribe from agent logs
    socket.on('unsubscribe', (data) => {
        const { agentId } = data;
        
        if (agentId === 'all') {
            socket.leave('all-agents');
        } else {
            socket.leave(`agent:${agentId}`);
        }
        
        logger.info('Client unsubscribed from logs', { socketId: socket.id, agentId });
    });

    // Handle log search requests
    socket.on('search', async (query) => {
        try {
            const results = await logManager.searchLogs(query);
            socket.emit('search-results', results);
        } catch (error) {
            socket.emit('search-error', { message: error.message });
        }
    });

    // Handle disconnection
    socket.on('disconnect', () => {
        logger.info('Log streaming client disconnected', { socketId: socket.id });
    });
});

// REST API endpoints
app.get('/api/logs/:agentId/recent', async (req, res) => {
    try {
        const { agentId } = req.params;
        const limit = parseInt(req.query.limit) || 100;
        
        const logs = await logManager.getRecentLogs(agentId, limit);
        res.json(logs);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/logs/search', async (req, res) => {
    try {
        const results = await logManager.searchLogs(req.query);
        res.json(results);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/agents/:agentId/logs/files', async (req, res) => {
    try {
        const { agentId } = req.params;
        const logFiles = [];
        
        const files = fs.readdirSync(config.logDir);
        for (const file of files) {
            if (file.startsWith(agentId)) {
                const filePath = path.join(config.logDir, file);
                const stats = fs.statSync(filePath);
                logFiles.push({
                    name: file,
                    size: stats.size,
                    modified: stats.mtime,
                    type: file.endsWith('.jsonl') ? 'structured' : 
                          file.endsWith('.cast') ? 'recording' : 'plaintext'
                });
            }
        }
        
        res.json(logFiles);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Health check
app.get('/health', async (req, res) => {
    try {
        await redisClient.ping();
        await esClient.ping();
        
        res.json({
            status: 'healthy',
            watchers: logManager.watchers.size,
            tails: logManager.tails.size,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(503).json({ status: 'unhealthy', error: error.message });
    }
});

// Initialize services
async function initialize() {
    try {
        await redisClient.connect();
        logger.info('Connected to Redis');

        // Ensure log directory exists
        if (!fs.existsSync(config.logDir)) {
            fs.mkdirSync(config.logDir, { recursive: true });
        }

        server.listen(config.port, () => {
            logger.info(`Log Streaming Service running on port ${config.port}`);
        });
    } catch (error) {
        logger.error('Failed to initialize Log Streaming Service:', error);
        process.exit(1);
    }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
    logger.info('SIGTERM received, shutting down gracefully');
    
    // Close all watchers
    for (const watcher of logManager.watchers.values()) {
        watcher.close();
    }
    
    // Stop all tails
    for (const tail of logManager.tails.values()) {
        tail.unwatch();
    }
    
    server.close();
    await redisClient.quit();
    process.exit(0);
});

// Start the service
initialize();