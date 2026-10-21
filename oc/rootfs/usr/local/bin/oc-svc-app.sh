#!/bin/bash
# The Claude Code sandbox piece — gated so a staging boot (sandbox_enabled
# = false) never writes the shared /workspace while the NAS sandbox lives.
# When enabled this is exactly the old container: startup.sh provisions tools,
# installs the cron entries, restores the Claude home from the newest
# claude-sync snapshot and exec's ttyd as PID 1.
set -u
if [ "${SANDBOX_ENABLED:-false}" = "true" ]; then
    exec bash /workspace/startup.sh
else
    echo "[oc-svc:app] sandbox DISABLED (sandbox_enabled=false) — sleeping (staging mode)"
    exec sleep infinity
fi