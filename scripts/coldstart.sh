#!/bin/bash
# coldstart.sh - bring up all containers from scratch
set -euo pipefail

# debug
#echo "pipefail set"

SECRETS="$(dirname "$0")/../secrets"
DATA="$(dirname "$0")/../data"
MODELS="$(dirname "$0")/../data/models"
LOG="$(dirname "$0")/../logs/ollama.log"

# debug
#printf "variables set\n"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

# debug
#printf "log function set\n"

if [[ ! -f "$SECRETS" ]]; then
    log "ERROR: secrets file not found at $SECRETS"
    exit 1
fi
source "$SECRETS"

# debug
#printf "secrets sourced\n"

log "=== Cold start ==="

# debug
#printf "checking tree\n"

mkdir -p "$MODELS" "${DATA}/openwebui" "${DATA}/searxng" "$(dirname "$LOG")" "${DATA}/obsidian/vault"
if [[ ! -f "${DATA}/obsidian/vault/index.md" ]]; then
    td=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    cat > "${DATA}/obsidian/vault/index.md" << EOF
---
type: index
title: Knowledge Bank
description: Root index for this OKF bundle
tags: []
timestamp: "$td"
---

# Knowledge Bank

Root concept index.
EOF
    log "Seeded initial OKF index.md in obsidian vault"
fi

# debug
#printf "checking network\n"

# --- Network ---
if ! podman network exists ollama-net; then
    podman network create ollama-net
    log "Created network ollama-net"
else
    log "Network ollama-net already exists"
fi

# --- preflight: refuse to run over existing containers ---
for c in ollama searxng openwebui; do
    if podman container exists "$c"; then
        log "ERROR: container '$c' already exists. Run scripts/stop.sh first"
        exit 1
    fi
done

# --- Ollama ---
# debug
#printf "initializing ollama container\n"

log "Starting ollama..."
podman run -d \
    --name ollama \
    --network ollama-net \
    -p 11434:11434 \
    -e OLLAMA_HOST=0.0.0.0:11434 \
    -v "${MODELS}:/root/.ollama:Z" \
    ollama/ollama:latest

# debug
#printf "ollama container present\n"

# --- Wait for Ollama to be ready ---
# debug
#printf "healthchecking ollama container\n"

log "Waiting for Ollama to be ready..."
for i in $(seq 1 30); do
    if podman exec ollama ollama list >/dev/null 2>&1; then
        log "Ollama ready after $((i * 2))s"
        # debug
        echo "ollama alive"
        break
    fi
    if [[ $i -eq 30 ]]; then
        log "ERROR: Ollama not ready after 60s, aborting"
        # debug
        echo "ollama dead"
        exit 1
    fi
    sleep 2
done

# debug
#printf "initialize model selection\n"

# --- Model selection ---
echo ""
echo "=== Models already installed ==="
EXISTING=$(podman exec ollama ollama list 2>/dev/null | tail -n +2)
if [[ -z "$EXISTING" ]]; then
    echo "  (none)"
else
    podman exec ollama ollama list
fi

echo ""
echo "=== Pull a new model ==="
echo "  1) llama3.1:8b       general-purpose  8B   ~6 GB RAM   128k ctx"
echo "  2) llama3.1:70b      general-purpose  70B  ~40 GB RAM  128k ctx"
echo "  3) mistral           fast, efficient   7B   ~4 GB RAM   32k ctx"
echo "  4) phi3              compact           3.8B ~2 GB RAM   128k ctx"
echo "  5) gemma2            balanced          9B   ~5 GB RAM   8k ctx"
echo "  6) codellama         code-focused      7B   ~4 GB RAM   16k ctx"
echo "  7) deepseek-coder    code-focused      6.7B ~4 GB RAM   16k ctx"
echo "  8) qwen2.5           strong reasoning  7B   ~5 GB RAM   128k ctx"
echo "  9) qwen2.5:32b       strong reasoning  32B  ~20 GB RAM  128k ctx"
echo " 10) custom            (type any model from ollama.com/library)"
echo ""
read -rp "Enter choice [1-10]: " choice

case $choice in
    1) MODEL="llama3.1:8b" ;;
    2) MODEL="llama3.1:70b" ;;
    3) MODEL="mistral" ;;
    4) MODEL="phi3" ;;
    5) MODEL="gemma2" ;;
    6) MODEL="codellama" ;;
    7) MODEL="deepseek-coder" ;;
    8) MODEL="qwen2.5" ;;
    9) MODEL="qwen2.5:32b" ;;
    10)
        read -rp "Enter model name (e.g. llama3.1:8b): " MODEL
        if [[ -z "$MODEL" ]]; then
            log "ERROR: no model name provided"
            exit 1
        fi
        ;;
    *)
        log "ERROR: invalid choice"
        exit 1
        ;;
esac

# debug
#printf "model selection complete\n"

log "Pulling model: $MODEL"
podman exec ollama ollama pull "$MODEL"
log "Model pull complete"

# --- SearXNG ---
# debug
#printf "initializing searxng\n"

log "Starting searxng..."
podman run -d \
    --name searxng \
    --network ollama-net \
    -p 8888:8080 \
    -v "${DATA}/searxng:/etc/searxng:Z" \
    -e SEARXNG_SECRET="${SEARXNG_SECRET_KEY}" \
    docker.io/searxng/searxng:latest
sleep 5

# debug
#printf "searxng alive\n"

# --- Open WebUI ---
# debug
#printf "initializing webui\n"

log "Starting openwebui..."
podman run -d \
    --name openwebui \
    --network ollama-net \
    -p 3000:8080 \
    -v "${DATA}/openwebui:/app/backend/data:Z" \
    -v "${DATA}/obsidian/vault:/vault:Z" \
    -e OLLAMA_BASE_URL=http://ollama:11434 \
    -e WEBUI_ADMIN_EMAIL="${WEBUI_ADMIN_EMAIL}" \
    -e WEBUI_ADMIN_PASSWORD="${WEBUI_ADMIN_PASSWORD}" \
    -e WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY}" \
    -e ENABLE_RAG_WEB_SEARCH=true \
    -e RAG_WEB_SEARCH_ENGINE=searxng \
    -e RAG_WEB_SEARCH_RESULT_COUNT=3 \
    -e RAG_WEB_SEARCH_CONCURRENT_REQUESTS=10 \
    -e SEARXNG_QUERY_URL="http://searxng:8080/search?q=<query>" \
    ghcr.io/open-webui/open-webui:latest

# debug
#printf "webui alive\n"

log "=== Cold start complete ==="
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
log "Ollama reachable at: http://${IP}:11434"
log "Open WebUI at: http://${IP}:3000"
