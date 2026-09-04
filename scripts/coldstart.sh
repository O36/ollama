#!/bin/bash
# coldstart.sh - bring up all containers from scratch
set -euo pipefail

# debug
#echo "pipefail set"

SECRETS="$(dirname "$0")/../secrets"
DATA="$(dirname "$0")/../data"
MODELS="$(dirname "$0")/../data/models"
IMPORTS="${DATA}/models/imports"
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

# --- validate required secrets ---
required_vars=(SEARXNG_SECRET_KEY WEBUI_ADMIN_EMAIL WEBUI_ADMIN_PASSWORD WEBUI_SECRET_KEY)
missing=()
for var in "${required_vars[@]}";do
    if [[ -z "${!var:-}" ]]; then
        missing+=("$var")
    fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
    log "ERROR: the following secrets are not set: ${missing[*]}"
    log "Edit '$SECRETS' and fill them out (see instructions in secrets.template)"
    exit 1
fi

# debug
#printf "secrets sourced\n"

log "=== Cold start ==="

# debug
#printf "checking tree\n"

mkdir -p "$MODELS" "${DATA}/openwebui" "${DATA}/searxng" "$(dirname "$LOG")" "${DATA}/obsidian/vault" "$IMPORTS"
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
    -v "${DATA}/models/imports:/imports:Z" \
    ollama/ollama:latest

# debug
#printf "ollama container present\n"

# --- Wait for Ollama to be ready ---
# debug
#printf "healthchecking ollama container\n"

log "Waiting for Ollama to be ready..."
for i in $(seq 1 12); do
    if podman exec ollama ollama list >/dev/null 2>&1; then
        log "Ollama ready after $((i * 5))s"
        # debug
        #printf "ollama alive\n"
        break
    fi
    if [[ $i -eq 12 ]]; then
        log "ERROR: Ollama not ready after 60s, aborting"
        # debug
        #printf "ollama dead\n"
        exit 1
    fi
    sleep 5
done

# debug
#printf "initialize model selection\n"

# --- Model selection ---
print_installed() {
    echo ""
    echo "=== Models already installed ==="
    EXISTING=$(podman exec ollama ollama list 2>/dev/null | tail -n +2)
    if [[ -z "$EXISTING" ]]; then
        echo "(none)"
    else
        podman exec ollama ollama list
    fi
}

# debug
#printf "starting selector\n"

while true; do
    print_installed

    echo ""
    echo "=== Pull a new model ==="
    echo "  0) skip                 continue without pulling anything new"
    echo "  1) huggingface          pull any GGUF model from huggingface.co/models"
    echo "  2) ollama               (type any model from ollama.com/library)"
    echo "  3) from local file      (import a .guff from local storage)"
    echo ""
    read -rp "Enter choice [0-3]: " choice

    case "$choice" in
        0)
            log "Skipping model pull"
            break
            ;;
        1)
            echo ""
            echo "Browse: https://huggingface.co/models?apps=ollama&sort=trending"
            echo "On a model page: 'Use this model' -> Ollama, copy the reference shown"
            echo "Format: org/repo:quantization (e.g. bartowski/Llama-3.2-1B-Instruct-GGUF:Q4_K_M)"
            read -rp "HF model: " HF_REF
            if [[ -z "$HF_REF" ]]; then
                log "ERROR: no model reference entered, try again"
                continue
            fi
            MODEL="hf.co/${HF_REF#hf.co/}"  # allowing users pasting the hf.co/ prefix
            ;;
        2)
            read -rp "Enter model name (e.g. llama3.1:8b): " MODEL
            if [[ -z "$MODEL" ]]; then
                log "ERROR: no model name entered, try again"
                continue
            fi
            ;;
        3)
            echo ""
            echo "Place your .gguf file in: $IMPORTS"
            echo "Files currently there:"
            ls -1 "$IMPORTS" 2>/dev/null | grep -v '^$' || echo "  (none)"
            read -rp "Filename: " GGUF_FILE
            GGUF_FILE=$(basename -- "$GGUF_FILE")   # stripping path traversal
            if [[ ! -f "${IMPORTS}"/"${GGUF_FILE}" ]]; then
                log "ERROR: '${GGUF_FILE}' not found in ${IMPORTS}, try again"
                continue
            fi
            read -rp "Name to give this model (e.g. mymodel:latest): " LOCAL_NAME
            if [[ ! "$LOCAL_NAME" =~ ^[a-zA-Z0-9_.:-]+$ ]]; then
                log "ERROR: invalid model name, try again"
                continue
            fi
            log "Importing ${GGUF_FILE} as ${LOCAL_NAME}..."
            if podman exec ollama sh -c "printf 'FROM /imports/%s\n' '${GGUF_FILE}' > /tmp/Modelfile && ollama create '${LOCAL_NAME}' -f /tmp/Modelfile";then
                log "Import complete: ${LOCAL_NAME}"
            else
                log "ERROR: import failed for ${GGUF_FILE}"
            fi
            echo ""
            read -rp "Pull/import another model? [y/N]: " again
            [[ "$again" =~ ^[Yy]$ ]] && continue || break
            ;;
        *)
            log "Invalid choice, try again"
            continue
            ;;
    esac

# debug
#printf "starting pull\n"

    log "Pulling model: $MODEL"
    if podman exec ollama ollama pull "$MODEL"; then
        log "Model pull complete: $MODEL"
    else
        log "ERROR: pull failed for '$MODEL' - check name, or note some HF repos (sharded GGUF) aren't supported yet"
    fi
    
    echo ""
    read -rp "Pull/import another model? [y/N]: " again
    [[ "$again" =~ ^[Yy]$ ]] || break
done

# debug
#printf "model selection finalized\n"

# --- SearXNG ---
# debug
#printf "initializing searxng\n"

if [[ ! -f "${DATA}/searxng/settings.yml" ]]; then
    cp "${DATA}/searxng/settings.yml.template" "${DATA}/searxng/settings.yml"
    log "Bootstrapped settings.yml from template"
fi

if ! grep -qF "secret_key: \"${SEARXNG_SECRET_KEY}\"" "${DATA}/searxng/settings.yml" 2>/dev/null; then
    sed -i "s|secret_key: \".*\"|secret_key: \"${SEARXNG_SECRET_KEY}\"|" "${DATA}/searxng/settings.yml"
    log "Injected searxng secret key into settings.yml"
fi

log "Starting searxng..."
podman run -d \
    --name searxng \
    --network ollama-net \
    -p 8888:8080 \
    -v "${DATA}/searxng:/etc/searxng:Z" \
    docker.io/searxng/searxng:latest

log "Waiting for searxng to be ready..."
for i in $(seq 1 12); do
    if podman exec searxng wget -qO- http://localhost:8080/ >/dev/null 2>&1; then
        log "Searxng ready after $((i * 5))s"
        break
    fi
    if [[ $i -eq 12 ]]; then
        log "WARNING: searxng not confirmed ready after 60s, continuing anyways"
    fi
    sleep 5
done

# debug
#printf "searxng finalized\n"

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

log "Waiting for OpenWebUI to be ready..."
for i in $(seq 1 36); do
    if podman exec openwebui bash -c 'exec 3<>/dev/tcp/localhost/8080' >/dev/null 2>&1; then
        log "OpenWebUI ready after $((i * 5))s"
        break
    fi
    if [[ $i -eq 36 ]]; then
        log "WARNING: OpenWebUI not confirmed ready after 180s, check manually"
    fi
    sleep 5
done

# debug
#printf "webui finalized\n"

echo ""
log "=== Cold start complete ==="
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
log "Ollama reachable at: http://${IP}:11434"
log "Open WebUI at: http://${IP}:3000"
echo ""
