#!/bin/bash
# ollama :cloud relay #2 (credit account) — was: ai-ollama-2, host port 11435.
# v2.0: state is LOCAL (/data/ollama2-home). Pure :cloud relay: no local models.
set -u
export HOME="/data/ollama2-home"
mkdir -p "$HOME/.ollama" 2>/dev/null || true
exec env OLLAMA_HOST=0.0.0.0:11435 \
    OLLAMA_MODELS=/data/ollama2-data \
    /usr/bin/ollama serve
