#!/bin/bash
# ollama :cloud relay #1 (caps account) — was: ai-ollama container, host port 11434.
# The NAS dir ollama-data IS the .ollama content; a $HOME symlink exposes it.
set -u
AIB="${AIB:-/share/aibundle}"
mkdir -p "$AIB/ollama-home"
ln -sfn "$AIB/ollama-data" "$AIB/ollama-home/.ollama"
exec env HOME="$AIB/ollama-home" \
    OLLAMA_HOST=0.0.0.0:11434 \
    OLLAMA_MODELS="$AIB/ollama-data/models" \
    /usr/bin/ollama serve