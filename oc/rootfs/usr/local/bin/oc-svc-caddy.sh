#!/bin/bash
# Caddy reverse proxy — was: ai-https-proxy. Publishes :8127 (the public
# https://17flo-prop.duckdns.org:8127 site). Loopback upstreams come from
# /etc/caddy/Caddyfile, derived per-boot by run.sh from the shared NAS
# Caddyfile. Data/config live on the NAS via the CIFS mount, so LE certs and
# the internal-CA state move with it.
set -u
AIB="${AIB:-/share/docker/ai-bundle}"
export XDG_DATA_HOME="$AIB/caddy-data"
export XDG_CONFIG_HOME="$AIB/caddy-config"
exec /usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile