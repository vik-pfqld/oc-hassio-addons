#!/bin/bash
# OpenClaw gateway — same invocation as the official image's Cmd
# (tini -- node openclaw.mjs gateway, cwd /app), with the compose envs and
# loopback upstreams. Runs as ROOT: the config/data dirs live on the CIFS
# mount where only the mounting uid (0) has effective ownership, so the
# image's node user cannot read them (EACCES).
set -u
cd /app || exit 1
exec /usr/bin/node openclaw.mjs gateway