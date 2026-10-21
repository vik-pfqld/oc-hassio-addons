#!/bin/bash
# Caddy reverse proxy — was: ai-https-proxy. Publishes :8127 (the public
# https://17flo-prop.duckdns.org:8127 site). Loopback upstreams come from
# /etc/caddy/Caddyfile, derived per-boot by run.sh from the shared NAS
# Caddyfile. Data/config live on the NAS via the CIFS mount, so LE certs and
# the internal-CA state move with it.
set -u
AIB="${AIB:-/share/aibundle}"
# The original caddy container bound the NAS dirs at /data and /config and the
# image sets XDG_* to exactly those paths; the Caddyfile references
# /data/caddy/certs/*.pem absolutely. Recreate that layout here.
# (run.sh has already read /data/options.json by the time we run.)
[ -e /data ] && [ ! -L /data ] && rm -rf /data
ln -sfn "$AIB/caddy-data" /data
[ -e /config ] && [ ! -L /config ] && rm -rf /config
ln -sfn "$AIB/caddy-config" /config
export XDG_DATA_HOME=/data
export XDG_CONFIG_HOME=/config
exec /usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile