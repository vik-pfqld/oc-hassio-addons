#!/bin/bash
# Caddy reverse proxy — was: ai-https-proxy. Publishes :8127 (the public
# site). v2.0.1: state is LOCAL mirroring the old layout exactly — XDG_DATA_HOME
# = /data (so the Caddyfile's /data/caddy/certs/... literal paths work), config
# state at /config (local). The Caddyfile is derived per-boot by run.sh.
set -u
export XDG_DATA_HOME=/data
export XDG_CONFIG_HOME=/config
exec /usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
