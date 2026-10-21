#!/bin/bash
# OC Stack healthcheck (Docker HEALTHCHECK target; the supervisor waits for
# health to mark the add-on "started"). Healthy = caddy's local admin API
# answering + both ollama relays + (sandbox option on) ttyd listening.
# NOTE: :8127 cannot be probed over plain http (TLS-only) and https probes
# hit SNI walls from inside — the caddy admin port is the reliable signal.
set -u
ok=0
curl -s -o /dev/null http://127.0.0.1:2019/config && ok=$((ok+1))
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
