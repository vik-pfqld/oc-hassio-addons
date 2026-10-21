#!/bin/bash
# OC Stack — DuckDNS (17flo-prop.duckdns.org) cert renewal via acme.sh.
# State: /data/acme.sh (LE account key + DuckDNS token; seeded 21 Oct 2026
# from the NAS sandbox's /root/.acme.sh). Its recorded install paths
# (Le_RealKeyPath / Le_RealFullChainPath) point at
# /workspace/property_tracker/certs/duckdns/ — --cron renews AND installs
# there; this script mirrors into caddy's live dir and reloads caddy
# whenever the files changed. Runs daily from /etc/cron.d/oc-acme-renew
# (installed by run.sh). Safe to run any time.
set -u
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
AH=/data/acme.sh
WK=/workspace/property_tracker/certs/duckdns
CD=/data/caddy/certs
[ -x "$AH/acme.sh" ] || { echo "[oc-acme] no $AH/acme.sh — not seeded, exiting"; exit 0; }
echo "[oc-acme] renewal check $(date -u '+%F %T') UTC"
"$AH/acme.sh" --home "$AH" --cron || echo "[oc-acme] WARN: --cron rc=$? (continuing)"
if [ -f "$WK/fullchain.pem" ] && ! cmp -s "$WK/fullchain.pem" "$CD/fullchain.pem" 2>/dev/null; then
    cp -f "$WK/fullchain.pem" "$CD/fullchain.pem"
    cp -f "$WK/key.pem" "$CD/key.pem"
    echo "[oc-acme] cert files updated in $CD — reloading caddy"
    /usr/local/bin/caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 \
        && echo "[oc-acme] caddy reloaded OK" \
        || echo "[oc-acme] WARN: caddy reload failed — retries next run"
else
    echo "[oc-acme] caddy certs unchanged"
fi
echo "[oc-acme] live cert validity:"
openssl x509 -noout -subject -dates -in "$CD/fullchain.pem" 2>/dev/null || echo "[oc-acme] openssl unavailable"
exit 0