#!/bin/bash
# maint.sh - maintenance tool for the ollama-stack
set -euo pipefail

DATA="$(dirname "$0")/../data"
LOG="$(dirname "$0")/../logs/ollama.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
log "Starting maintenance"

while true; do
    echo ""
    echo "=== Maintenance ollama-stack ==="
    echo "  0) Close                Quit back to the cli"
    echo "  1) Fix permissions      Reclaim host ownership of container-written data dirs"
    echo "  2) Purge models         remove models from memory"
    echo "  3) Reset WebUI          flushes the WebUI"
    echo ""
    read -rp "Enter choice [0-3]: " choice

    case "$choice" in
        0)
            log "Quitting maintenance"
            break
            ;;
        1)
            echo ""
            echo "WARNING: this will overwrite the ownership of container-written data (models, obsidian, openwebui, and searxng) to be owned by who runs this script"
            read -rp "Overwrite ownership [y/N]: " writeownership
            case "$writeownership" in
                [Yy])
                    echo "Fixing ownership of ${DATA}/{models,obsidian,openwebui,searxng}..."
                    podman unshare chown -R 0:0 "${DATA}/models" "${DATA}/obsidian" "${DATA}/openwebui" "${DATA}/searxng"
                    echo "Done, run 'ls -lahR ${DATA}' to verify ownership"
                    ;;
                *)
                    echo "Cancelled"
                    ;;
            esac
            ;;
        2)
            echo ""
            echo "=== Purge models ==="
            EXISTING=$(podman exec ollama ollama list 2>/dev/null | tail -n +2)
            if [[ -z "$EXISTING" ]]; then
                echo "(none)"
                echo ""
                continue
            fi
            podman exec ollama ollama list
            echo ""
            read -rp "Model to purge? [modelname/blank to cancel]: " purgetarget
            if [[ -z "$purgetarget" ]]; then
                echo "Cancelled"
                continue
            fi
            read -rp "Purge '${purgetarget}'? this cannot be undone. [y/N]: " confirmpurge
            if [[ ! "$confirmpurge" =~ ^[Yy]$ ]]; then
                echo "Cancelled"
                continue
            fi
            if podman exec ollama ollama rm "$purgetarget"; then
                log "$purgetarget purged"
            else
                log "ERROR: failed to purge '$purgetarget' - match name exactly"
            fi
            echo ""
            ;;
        3)
            echo ""
            echo "=== Reset WebUI ==="
            echo " 0) Back                Return to main menu"
            echo " 1) Full wipe           !nuclear! Delete everything (DB, history, uploads, vector_db, cache)"
            echo " 2) Chat history only   Clear conversations, keep accounts and settings"
            echo " 3) RAG/vector cache    Clear vector_db and cache only, keep everything else"
            echo ""
            read -rp "Enter choice [0-3]: " wipechoice
            case "$wipechoice" in
                0)
                    echo "Cancelled"
                    ;;
                1)
                    read -rp "Full wipe of OpenWebUI data - this deletes everything including admin account, and cannot be undone [y/N]: " confirmwipe
                    if [[ "$confirmwipe" =~ ^[Yy]$ ]]; then
                        rm -rf "${DATA}/openwebui"/*
                        log "OpenWebUI fully wiped - next coldstart will bootstrap a fresh admin account"
                    else
                        echo "Cancelled"
                    fi
                    ;;
                2)
                    read -rp "Clear all chat history? This cannot be undone. [y/N]: " confirmwipe
                    if [[ "$confirmwipe" =~ ^[Yy]$ ]]; then
                        podman exec openwebui rm -f /app/backend/data/webui.db /app/backend/data/webui.db-shm /app/backend/data/webui.db-wal
                        log "OpenWebUI chat history cleared - restart the openwebui container to take effect"
                        read -rp "Restart container now? [y/N]: " confirmrestart
                        if [[ "$confirmrestart" =~ ^[Yy]$ ]]; then
                            podman restart openwebui
                        else
                            echo "Container not restarted"
                        fi
                    else
                        echo "Cancelled"
                    fi
                    ;;
                3)
                    read -rp "Clear RAG/vector cache? [y/N]: " confirmwipe
                    if [[ "$confirmwipe" =~ ^[Yy]$ ]]; then
                        rm -rf "${DATA}/openwebui/vector_db"/* "${DATA}/openwebui/cache"/*
                        log "OpenwebUI RAG/vector cache cleared"
                    else
                        echo "Cancelled"
                    fi
                    ;;
                *)
                    log "Invalid choice, try again"
                    ;;
            esac
            echo ""
            ;;
        *)
            log "Invalid choice, try again"
            continue
            ;;
    esac
done

