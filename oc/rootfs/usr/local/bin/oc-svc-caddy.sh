#!/bin/bash
# Caddy reverse proxy — was: ai-https-proxy. Publishes :8127 (the public
# https://17flo-prop.duckdns.org:8127 site). Upstream + cert paths are
# rewritten by run.sh into /etc/caddy/Caddyfile. Caddy's own state (ACME
# cache, pki, instance uuid) lives on the NAS via the CIFS mount exactly as
# before (XDG_DATA_HOME=/data in the old image).
set -u
AIB="${AIB:-/share/aibundle}"
export XDG_DATA_HOME="$AIB/caddy-data"
export XDG_CONFIG_HOME="$AIB/caddy-config"
exec /usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile