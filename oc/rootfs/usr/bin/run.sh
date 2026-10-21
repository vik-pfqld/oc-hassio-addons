#!/bin/bash
# OC Stack add-on — supervisor / orchestrator.
#
# Mirrors the NAS docker-compose 'oc' stack with every service inside ONE
# container:
#   ollama (11434) + ollama2 (11435) | openclaw (18789) | caddy (:8127 host)
#   chromium + noVNC (9222 / 8300)   | app = bash /workspace/startup.sh
#   (ttyd 7681, proxy 8787, viewer 8000, uvicorn 18127 via PT_WEB_PORT,
#    portal 9001, gate 8899, crons)
#
# All persistent data stays on the NAS md1 volume, seen through the HA
# Supervisor CIFS mount at /share/aibundle (zero copy). The sandbox piece is
# opt-in via the `sandbox_enabled` option so a staging boot can't write the
# shared workspace while the NAS sandbox is still the live one.
set -u

log() { echo "[oc-supervisor] [$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
export AIB="${AIB:-/share/aibundle}"
export SANDBOX_ENABLED=false CHROMIUM_ENABLED=true

# ---------------------------------------------------------------- options ---
OPTS=/data/options.json
if [ -f "$OPTS" ]; then
    SANDBOX_ENABLED="$(jq -r 'if (.sandbox_enabled | type) == "boolean" then .sandbox_enabled else "false" end' "$OPTS" 2>/dev/null || echo false)"
    CHROMIUM_ENABLED="$(jq -r 'if (.chromium_enabled | type) == "boolean" then .chromium_enabled else "true" end' "$OPTS" 2>/dev/null || echo true)"
    NOVNC_PW="$(jq -r 'if (.novnc_password | type) == "string" then .novnc_password else "" end' "$OPTS" 2>/dev/null || true)"
else
    log "WARNING: no /data/options.json — using defaults"
fi
[ -n "$SANDBOX_ENABLED" ]  || SANDBOX_ENABLED=false
[ -n "$CHROMIUM_ENABLED" ] || CHROMIUM_ENABLED=true
[ -n "$NOVNC_PW" ]         || NOVNC_PW=changeme123
export SANDBOX_ENABLED CHROMIUM_ENABLED

# ---------------------------------------------------------------- env ------
# Loopback rewrites: inside one container the old compose DNS aliases
# (ollama, ollama2, ai-claudecode-web, openclaw) don't resolve.
export QUOTA_UPSTREAM="http://127.0.0.1:11434"
export QUOTA_UPSTREAM_REMAP="http://ollama:11434=http://127.0.0.1:11434,http://ollama2:11434=http://127.0.0.1:11435"
export QUOTA_PROXY_URL="http://127.0.0.1:8787"
export PT_WEB_PORT="18127"          # caddy itself owns the host-facing :8127
export OLLAMA_BASE_URL="http://127.0.0.1:11434"
export ANTHROPIC_BASE_URL="http://127.0.0.1:11434"
# OpenClaw gateway env (identical to the NAS compose envs)
export NODE_ENV=production
export OPENCLAW_GATEWAY_MODE=local
export OPENCLAW_GATEWAY_BIND=custom
export OPENCLAW_CUSTOM_BIND_HOST=0.0.0.0
export OPENCLAW_GATEWAY_INSECURE=true
export OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH=true
export GATEWAY_ALLOW_UNCONFIGURED=true
export OPENCLAW_GATEWAY_PASSWORD=ollama
export ANTHROPIC_API_KEY="local_ollama_bypass"
export ANTHROPIC_MODEL="glm-5.2:cloud"
export ANTHROPIC_DEFAULT_SONNET_MODEL="qwen3.6:cloud"
export ANTHROPIC_DEFAULT_OPUS_MODEL="minimax-m2.7:cloud"
export PYTHONUNBUFFERED=1

# --------------------------------------------------------- mount + symlinks -
for i in $(seq 1 90); do
    if [ -f "$AIB/Caddyfile" ] && [ -d "$AIB/workspace" ]; then break; fi
    [ $((i % 10)) = 1 ] && log "waiting for CIFS mount at $AIB (attempt $i/90)..."
    sleep 2
done
if [ ! -f "$AIB/Caddyfile" ] || [ ! -d "$AIB/workspace" ]; then
    log "FATAL: $AIB/Caddyfile or workspace not available — is the 'aibundle'"
    log "       Supervisor CIFS mount created and the NAS share reachable?"
    exit 1
fi
log "CIFS mount OK: $AIB"

# /workspace -> same NAS dir as the old ai-claudecode-web bind.
# (rm -rf on a symlink removes the link only, never the CIFS target.)
rm -rf /workspace && ln -s "$AIB/workspace" /workspace

# OpenClaw data paths — same layout the docker binds produced on the NAS.
for p in /app/config /app/workspace /app/sharedworkspace /home/node/.openclaw; do
    [ -L "$p" ] && rm -f "$p"
    if [ -e "$p" ]; then
        log "note: replacing image dir $p with symlink to openclaw-data"
        rm -rf "$p"
    fi
done
mkdir -p "$AIB/openclaw-data/workspace"
ln -s "$AIB/openclaw-data"           /app/config
ln -s "$AIB/openclaw-data/workspace" /app/workspace
ln -s "$AIB/workspace"               /app/sharedworkspace
ln -s "$AIB/openclaw-data"           /home/node/.openclaw

# Ollama identity homes: the NAS dirs ARE the .ollama content; give each
# instance a $HOME whose .ollama path points at its NAS dir.
mkdir -p "$AIB/ollama-home" "$AIB/ollama2-home"
ln -sfn "$AIB/ollama-data"  "$AIB/ollama-home/.ollama"
ln -sfn "$AIB/ollama2-data" "$AIB/ollama2-home/.ollama"

# Chromium profile (persisted Kasada cookies / logins).
mkdir -p "$AIB/chrome-profile"

# Caddyfile: derive the loopback variant from the NAS original every boot.
# Also rewrite the absolute /data/caddy/certs path (the old container bound
# caddy-data at /data; this add-on shares the real path directly).
mkdir -p /etc/caddy
sed -e 's/ai-claudecode-web:8899/127.0.0.1:8899/g' \
    -e 's/ai-claudecode-web:8127/127.0.0.1:18127/g' \
    -e 's/ai-claudecode-web:8000/127.0.0.1:8000/g' \
    -e 's/ai-claudecode-web:9001/127.0.0.1:9001/g' \
    -e 's/openclaw:18789/127.0.0.1:18789/g' \
    -e "s|/data/caddy/certs/|$AIB/caddy-data/caddy/certs/|g" \
    "$AIB/Caddyfile" > /etc/caddy/Caddyfile
log "Caddyfile derived (loopback upstreams + certs path) from $AIB/Caddyfile"

# ---------------------------------------------------- service supervision ---
# Each service = one launcher script (rootfs/usr/local/bin/oc-svc-*.sh) run by
# a background loop that respawns it forever. run.sh itself is PID 1 (tini) —
# it launches the loops and only re-launches a loop if the loop bash died.
sup_loop() {
    local name="$1"; local script="$2"
    (
      while true; do
          echo "[oc-svc:$name] starting $script"
          "$script" >> "/run/oc-log-$name.log" 2>&1
          echo "[oc-svc:$name] EXITED rc=$? (see /run/oc-log-$name.log) — respawn in 3s"
          sleep 3
      done
    ) &
    echo "$!" > "/run/oc-sup-$name.pid"
    echo "$script" > "/run/oc-sup-$name.cmd"
}

sup_loop ollama    /usr/local/bin/oc-svc-ollama.sh
sup_loop ollama2   /usr/local/bin/oc-svc-ollama2.sh
sup_loop openclaw  /usr/local/bin/oc-svc-openclaw.sh
[ "$CHROMIUM_ENABLED" = "true" ] && sup_loop chromium /usr/local/bin/oc-chromium.sh \
    || log "chromium disabled by option"
sup_loop app       /usr/local/bin/oc-svc-app.sh

# Caddy last: reverse-proxies the services above; a short head start avoids
# a thundering herd of 502s at boot. During staging (sandbox off) caddy serves
# /openclaw fine and 502s the sandbox routes — expected.
sleep 5
sup_loop caddy /usr/local/bin/oc-svc-caddy.sh

# --------------------------------------------------------------- hold PID1 --
log "all services launched — supervising"
while true; do
    sleep 30
    for f in /run/oc-sup-*.pid; do
        [ -f "$f" ] || continue
        name="$(basename "$f" .pid)"; name="${name#oc-sup-}"
        p="$(cat "$f" 2>/dev/null)"
        if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then
            script="$(cat "/run/oc-sup-$name.cmd" 2>/dev/null)"
            if [ -n "$script" ] && [ -x "$script" ]; then
                log "supervisor loop '$name' (pid $p) died — relaunching $script"
                sup_loop "$name" "$script"
            else
                rm -f "$f"
            fi
        fi
    done
done