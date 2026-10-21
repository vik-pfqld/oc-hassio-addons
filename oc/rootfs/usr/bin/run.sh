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
export SANDBOX_ENABLED=false CHROMIUM_ENABLED=true OPENCLAW_ENABLED=false

# ---------------------------------------------------------------- options ---
OPTS=/data/options.json
if [ -f "$OPTS" ]; then
    SANDBOX_ENABLED="$(jq -r 'if (.sandbox_enabled | type) == "boolean" then .sandbox_enabled else "false" end' "$OPTS" 2>/dev/null || echo false)"
    CHROMIUM_ENABLED="$(jq -r 'if (.chromium_enabled | type) == "boolean" then .chromium_enabled else "true" end' "$OPTS" 2>/dev/null || echo true)"
    OPENCLAW_ENABLED="$(jq -r 'if (.openclaw_enabled | type) == "boolean" then .openclaw_enabled else "false" end' "$OPTS" 2>/dev/null || echo false)"
    SIDE_BY_SIDE="$(jq -r 'if (.side_by_side | type) == "boolean" then .side_by_side else "false" end' "$OPTS" 2>/dev/null || echo false)"
    NOVNC_PW="$(jq -r 'if (.novnc_password | type) == "string" then .novnc_password else "" end' "$OPTS" 2>/dev/null || true)"
else
    log "WARNING: no /data/options.json — using defaults"
fi
[ -n "$SANDBOX_ENABLED" ]   || SANDBOX_ENABLED=false
[ -n "$CHROMIUM_ENABLED" ]  || CHROMIUM_ENABLED=true
[ -n "$OPENCLAW_ENABLED" ]  || OPENCLAW_ENABLED=false
[ -n "$SIDE_BY_SIDE" ]      || SIDE_BY_SIDE=false
[ -n "$NOVNC_PW" ]          || NOVNC_PW=changeme123
export SANDBOX_ENABLED CHROMIUM_ENABLED OPENCLAW_ENABLED SIDE_BY_SIDE
log "options: sandbox=$SANDBOX_ENABLED chromium=$CHROMIUM_ENABLED openclaw=$OPENCLAW_ENABLED side_by_side=$SIDE_BY_SIDE"

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

# v2.0 DATA MODEL: the workspace is a LOCAL COPY on the add-on's /data (the
# HA SSD); only bulk media (downloads) stays on the NAS, read-mostly, via the
# CIFS mount. ollama + caddy state are local too. The NAS originals are never
# written by this add-on.
if [ ! -d /data/workspace ]; then
    log "FATAL: /data/workspace (the copied workspace) not present — copy step missing"
    exit 1
fi
rm -rf /workspace && ln -s /data/workspace /workspace

# Downloads stay shared: the local copy has no downloads dir, so wire it to
# the NAS via the CIFS mount (read-mostly; the viewer's index DB lives LOCAL
# under /data/viewer-work, see below).
rm -rf /data/workspace/downloads && ln -s "$AIB/workspace/downloads" /data/workspace/downloads

# Scrolller viewer local index root: its DB is <root>/_browser_state.sqlite3
# (viewer.py:43) inside the scanned root — give it a LOCAL root with
# subfolder symlinks into the shared downloads so it never double-writes the
# NAS viewer's DB during side-by-side.
mkdir -p /data/viewer-work
if [ -d "$AIB/workspace/downloads" ]; then
    for d in "$AIB/workspace/downloads"/*/; do
        [ -d "$d" ] && ln -sfn "$d" "/data/viewer-work/$(basename "$d")"
    done
fi
# Patch the copied startup.sh so the viewer scans the local root (idempotent).
sed -i 's| -m scrolller_scraper\.viewer /workspace/downloads | -m scrolller_scraper.viewer /data/viewer-work |g' \
    /data/workspace/startup.sh 2>/dev/null || true

# Ollama: local state dirs (identities + any models); NAS dirs left alone.
mkdir -p /data/ollama-data /data/ollama2-data

# OpenClaw data paths — same layout the docker binds produced on the NAS.
# NOTE: this only matters when openclaw runs INSIDE the add-on (option). When
# disabled, the NAS gateway keeps running and caddy routes /openclaw to it.
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

# Caddy: LOCAL state mirroring the old container layout — the old bind put
# caddy-data AT /data, and the Caddyfile's literal cert path is
# /data/caddy/certs/... — so XDG_DATA_HOME=/data and that exact path must
# exist on the local SSD. Seed once from the NAS copy (read-only source).
# (v1.x had a /data/caddy-data -> CIFS symlink from debugging; remove it.)
[ -L /data/caddy-data ] && rm -f /data/caddy-data
rm -rf /data/caddy-data 2>/dev/null
mkdir -p /data/caddy/certs /config
if [ ! -f /data/caddy/certs/fullchain.pem ]; then
    cp -a "$AIB/caddy-data/caddy/certs/." /data/caddy/certs/ 2>/dev/null && log "seeded caddy certs to /data/caddy/certs"
fi

# Caddyfile: derive the loopback variant from the NAS original every boot.
# (cert paths stay /data/caddy/certs — now the LOCAL copy)
mkdir -p /etc/caddy
# Where the /openclaw route lands depends on whether the gateway is bundled
# (127.0.0.1) or still runs on the NAS during the migration.
if [ "$OPENCLAW_ENABLED" = "true" ]; then
    OC_UPSTREAM="127.0.0.1:18789"
else
    OC_UPSTREAM="192.168.1.47:18789"
fi
sed -e 's/ai-claudecode-web:8899/127.0.0.1:8899/g' \
    -e 's/ai-claudecode-web:8127/127.0.0.1:18127/g' \
    -e 's/ai-claudecode-web:8000/127.0.0.1:8000/g' \
    -e 's/ai-claudecode-web:9001/127.0.0.1:9001/g' \
    -e "s|openclaw:18789|$OC_UPSTREAM|g" \
    "$AIB/Caddyfile" > /etc/caddy/Caddyfile
log "Caddyfile derived (loopback upstreams; /openclaw -> $OC_UPSTREAM)"

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
[ "$OPENCLAW_ENABLED" = "true" ] && sup_loop openclaw /usr/local/bin/oc-svc-openclaw.sh \
    || log "openclaw disabled by option (NAS gateway keeps serving /openclaw)"
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