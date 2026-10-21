#!/bin/bash
# ollama :cloud relay #1 (caps account) — was: ai-ollama container, host port 11434.
# v2.0: state is LOCAL (/data/ollama-home). Pure :cloud relay: no local models.
set -u
export HOME="/data/ollama-home"
mkdir -p "$HOME/.ollama" 2>/dev/null || true
exec env OLLAMA_HOST=0.0.0.0:11434 \
    OLLAMA_MODELS=/data/ollama-data \
    /usr/bin/ollama serve