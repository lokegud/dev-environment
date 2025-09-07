#!/bin/bash
# Terminal wrapper script for comprehensive logging

# Environment variables
AGENT_ID=${AGENT_ID:-"unknown"}
SESSION_ID=${SESSION_ID:-$(uuidgen 2>/dev/null || echo "session-$(date +%s)")}
LOG_DIR="/var/log/agent-terminal"
COMMAND_LOG="${LOG_DIR}/${AGENT_ID}-commands.log"
SESSION_LOG="${LOG_DIR}/${AGENT_ID}-session-${SESSION_ID}.log"
STRUCTURED_LOG="${LOG_DIR}/${AGENT_ID}-structured.jsonl"

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Function to log structured data
log_event() {
    local event_type=$1
    local data=$2
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"agent_id\":\"${AGENT_ID}\",\"session_id\":\"${SESSION_ID}\",\"event_type\":\"${event_type}\",\"data\":${data}}" >> "${STRUCTURED_LOG}"
}

# Log session start
log_event "session_start" "{\"command\":\"$*\",\"pid\":$$,\"user\":\"$(whoami)\",\"pwd\":\"$(pwd)\"}"

# Setup command logging via bash PROMPT_COMMAND
export PROMPT_COMMAND='echo "$(date +"%Y-%m-%d %H:%M:%S") [${AGENT_ID}] $(history 1)" >> '"${COMMAND_LOG}"

# Stream logs to central collector if configured
if [ -n "${LOG_COLLECTOR_URL}" ]; then
    # Start background process to stream logs
    (
        tail -F "${STRUCTURED_LOG}" 2>/dev/null | while IFS= read -r line; do
            curl -X POST "${LOG_COLLECTOR_URL}/logs" \
                -H "Content-Type: application/json" \
                -H "X-Agent-ID: ${AGENT_ID}" \
                -d "${line}" 2>/dev/null || true
        done
    ) &
    STREAM_PID=$!
fi

# Function to cleanup on exit
cleanup() {
    log_event "session_end" "{\"exit_code\":$?,\"duration\":$(($(date +%s) - START_TIME))}"
    [ -n "${STREAM_PID}" ] && kill "${STREAM_PID}" 2>/dev/null
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Record start time
START_TIME=$(date +%s)

# Start recording with asciinema if configured
if [ "${ENABLE_RECORDING}" = "true" ]; then
    asciinema rec --quiet --append --overwrite \
        -t "Agent ${AGENT_ID} - Session ${SESSION_ID}" \
        "${LOG_DIR}/${AGENT_ID}-recording-${SESSION_ID}.cast" \
        -c "$*"
else
    # Execute the actual command with script for logging
    script -q -f -c "$*" "${SESSION_LOG}"
fi

exit $?