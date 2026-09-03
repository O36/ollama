#!/bin/bash
# stop.sh - gracefully stop ollama

set -euo pipefail
LOG="$(dirname "$0")/../logs/ollama.log"

log() { echo "[$(date '+%Y-%m-%d %H.%M:%S')] $*" | tee -a "$LOG"; }

log "=== stopping ollama services ==="
if podman container exists ollama; then
    log "stopping ollama container..."
    podman stop ollama
else
    log "container ollama not found..."
fi

log "=== stopping searxng services ==="
if podman container exists searxng; then
    log "stopping searxng container..."
    podman stop searxng
else
    log "container searxng not found..."
fi

log "=== stopping openwebui services ==="
if podman container exists openwebui; then
    log "stopping openwebui container..."
    podman stop openwebui
else
    log "container openwebui not found..."
fi

log "=== stop complete ==="

podman ps -a

echo ""
read -rp "remove containers? [y/n] " answer
if [[ "$answer" != "y" ]]; then
    log "containers kept, exiting"
    podman ps -a
    exit 0
fi

log "removing containers..."
for container in ollama searxng openwebui; do
    if podman container exists "$container"; then
        podman rm "$container"
        log "removed $container"
    else
        log "$container not found, skipping..."
    fi
done
log "containers removed, use coldstart to rebuild"

podman ps -a
