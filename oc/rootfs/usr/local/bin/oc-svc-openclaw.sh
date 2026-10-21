#!/bin/bash
# OpenClaw gateway — same invocation as the official image's Cmd
# (tini -- node openclaw.mjs gateway, cwd /app), with the compose envs and
# loopback upstreams. Runs as the node user to match file ownership on the
# NAS volume (falls back to root if the image has no node user).
set -u
if id node >/dev/null 2>&1; then
    cd /app || exit 1
    exec runuser -u node -- /usr/bin/node openclaw.mjs gateway
else
    exec /usr/bin/node openclaw.mjs gateway
fi