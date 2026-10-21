#!/bin/bash
# OpenClaw gateway — same invocation as the official image's Cmd
# (tini -- node openclaw.mjs gateway, cwd /app), with the compose envs and
# loopback upstreams. Runs as the image's node user (uid 1000) exactly like
# the NAS container did — the NAS-side permission sweep made the CIFS-backed
# openclaw-data readable/writable for it again.
set -u
cd /app || exit 1
if id node >/dev/null 2>&1; then
    exec runuser -u node -- /usr/bin/node openclaw.mjs gateway
else
    exec /usr/bin/node openclaw.mjs gateway
fi