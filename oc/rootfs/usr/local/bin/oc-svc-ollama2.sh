#!/bin/bash
# ollama :cloud relay #2 (credit account) — was: ai-ollama-2, host port 11435.
set -u
AIB="${AIB:-/share/aibundle}"
mkdir -p "$AIB/ollama2-home"
ln -sfn "$AIB/ollama2-data" "$AIB/ollama2-home/.ollama"
exec env HOME="$AIB/ollama2-home" \
    OLLAMA_HOST=0.0.0.0:11435 \
    OLLAMA_MODELS="$AIB/ollama2-data/models" \
    /usr/bin/ollama serve