#!/bin/bash
# The Claude Code sandbox piece — gated so a staging boot (sandbox_enabled
# = false) never writes the workspace while the NAS sandbox lives. When
# enabled this is the old container: startup.sh provisions tools, installs
# the cron entries, restores the Claude home from the newest claude-sync
# snapshot and exec's ttyd as PID 1.
#
# v2.0 side_by_side mode: while enabled, remove the divvy autobook/watch and
# morning-reserve cron entries right after startup.sh creates them (keeps
# claude-snapshot + e2scrub), so both stacks can run simultaneously without
# double-booking or duplicate predictions. Re-enabled at decommission.
set -u
if [ "${SANDBOX_ENABLED:-false}" = "true" ]; then
    if [ "${SIDE_BY_SIDE:-false}" = "true" ]; then
        (
          sleep 30
          rm -f /etc/cron.d/divvy-autobook /etc/cron.d/divvy-watch* 2>/dev/null
          rm -f /etc/cron.d/morning-reserve 2>/dev/null
          service cron restart 2>/dev/null || /usr/sbin/cron 2>/dev/null || true
          echo "[oc-svc:app] side-by-side: divvy/morning-reserve crons disabled"
        ) &
    fi
    exec bash /workspace/startup.sh
else
    echo "[oc-svc:app] sandbox DISABLED (sandbox_enabled=false) — sleeping (staging mode)"
    exec sleep infinity
fi