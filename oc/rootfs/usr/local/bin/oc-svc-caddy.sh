#!/bin/bash
# Caddy reverse proxy — was: ai-https-proxy. Publishes :8127 (the public
# site). v2.0: all caddy state is LOCAL (the add-on's /data): certs seeded
# once from the NAS copy, config = /data/caddy-config. The Caddyfile is
# derived per-boot by run.sh (loopback upstreams, ports unchanged).
# Mirror the old image's XDG envs pointing at the local dirs.
set -u
export XDG_DATA_HOME=/data/caddy-data
export XDG_CONFIG_HOME=/data/caddy-config
mkdir -p /config
exec /usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile