#!/bin/bash
# Warm Chromium + noVNC for the property-tracker scraper (bundled into the OC
# add-on). Replaces the linuxserver/chromium stack: CDP stays reachable the
# same way — Chrome hard-binds its DevTools port to 127.0.0.1:9223, so socat
# forwards 0.0.0.0:9222 → it — and the noVNC web UI on :8300 preserves the
# manual warm-up flow (browse realestate.com.au, log in, cookies persist).
set -u
export DISPLAY=:99
PROFILE="${OC_CHROME_PROFILE:-/data/chrome-profile}"
mkdir -p "$PROFILE"

# 1) Virtual display (sized to be usable in a browser tab for warm-ups)
if ! pgrep -f "Xvfb :99" >/dev/null 2>&1; then
    Xvfb :99 -screen 0 1440x1024x24 -nolisten tcp &
    echo "[oc-chromium] Xvfb started"
fi
sleep 1

# 2) VNC server on :5900 with a password file (created by oc-chromium-pass)
x11vnc -display :99 -forever -shared -rfbauth /run/oc-vnc.pass -quiet &
echo "[oc-chromium] x11vnc started"

# 3) noVNC web client on :8300 (VNC password prompt is honoured by noVNC)
websockify --web /usr/share/novnc 8300 localhost:5900 &
echo "[oc-chromium] noVNC on :8300"

# 4) Chromium (headful under Xvfb, debug port on loopback only)
#    CHROME_CLI of the old container: --user-data-dir=/config
#    --remote-debugging-port=9223  (+ shm fix because add-ons get small /dev/shm)
chromium \
    --user-data-dir="$PROFILE" \
    --remote-debugging-port=9223 \
    --disable-dev-shm-usage \
    --disable-crash-reporter \
    --no-sandbox \
    --no-first-run \
    --lang=en-AU &
echo "[oc-chromium] chromium started (cdp 127.0.0.1:9223, user-data-dir=$PROFILE)"

# 5) CDP sidecar: 0.0.0.0:9222 -> 127.0.0.1:9223 (same socat line the old
#    rea-chrome-cdp-proxy ran)
socat TCP-LISTEN:9222,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:9223 &
echo "[oc-chromium] socat :9222 -> 127.0.0.1:9223 started"

# Keep this script's direct children (xvfb et al) alive; the sup_loop wrapper
# in run.sh respawns the whole script if it ever exits.
wait