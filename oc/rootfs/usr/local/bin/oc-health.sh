#!/bin/bash
# OC Stack healthcheck (Docker HEALTHCHECK target; the supervisor waits for
# health to mark the add-on "started", and Portainer shows it too).
# Healthy = caddy admin up + both ollama relays answering + (when the sandbox
# option is on) ttyd listening. Chromium/noVNC are excluded: the browser is
# on-demand-ish and must not flap the whole add-on's health.
set -u
ok=0
curl -sf -o /dev/null http://127.0.0.1:8127/ && ok=$((ok+1))
curl -sf -o /dev/null http://127.0.0.1:11434/api/version && ok=$((ok+1))
curl -sf -o /dev/null http://127.0.0.1:11435/api/version && ok=$((ok+1))
SBE=$(jq -r '.sandbox_enabled // false' /data/options.json 2>/dev/null || echo false)
if [ "$SBE" = "true" ]; then
    curl -sf -o /dev/null http://127.0.0.1:7681/ && ok=$((ok+1))
    [ $ok -ge 4 ] || exit 1
else
    [ $ok -ge 3 ] || exit 1
fi
exit 0