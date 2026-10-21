# OC Stack mega add-on — one container hosting the whole ai-bundle:
#   ollama x2 (cloud relays, 11434/11435), OpenClaw gateway, Caddy reverse
#   proxy, the Claude Code sandbox (ttyd 7681 + python services) and the
#   warm Chromium + noVNC scraper (CDP 9222, web 8300).
#
# Base = official openclaw image (Debian 12, node 24, tini, /app source tree,
# /usr/local/bin/openclaw) so the gateway needs no re-derivation.

ARG BUILD_FROM=openclaw/openclaw:latest
FROM ${BUILD_FROM}

# The openclaw image defaults to its node user for runtime AND build; apt
# needs root here, and the add-on itself runs as root.
USER root

# Debian bookworm deps: the sandbox toolchain + the chromium/noVNC graphics
# stack + caddy/ollama download helpers. startup.sh re-runs apt itself if
# anything is missing (idempotent), this just removes the cold-boot penalty.
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      python3 python3-pip python3-venv curl ca-certificates cron tmux jq socat \
      xz-utils unzip git zstd xvfb x11vnc websockify novnc chromium fonts-liberation \
 && rm -rf /var/lib/apt/lists/*

# Caddy — prebuilt binary from the official download API.
RUN curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" \
      -o /usr/local/bin/caddy && chmod 0755 /usr/local/bin/caddy

# Ollama — official static tarball (binary + libs only, no GPU needed: these
# instances are pure :cloud relays with zero local models). The linux asset
# is .tar.zst as of ollama v0.40.x.
RUN curl -fsSL -o /tmp/ollama.tar.zst \
      "https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tar.zst" \
 && tar --zstd -C /usr -xf /tmp/ollama.tar.zst \
 && rm -f /tmp/ollama.tar.zst && chmod 0755 /usr/bin/ollama

COPY rootfs/ /

# Ensure the bundled scripts are executable regardless of git exec-bit loss.
RUN chmod 0755 /usr/bin/run.sh /usr/bin/oc-chromium-pass /usr/local/bin/oc-health.sh \

      /usr/local/bin/oc-chromium.sh /usr/local/bin/oc-logs /usr/local/bin/oc-svc-*.sh

# The HA add-on runs as root; tini (from the base image) reaps the
# supervisor's children.
ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/usr/bin/run.sh"]

# Add-on health contract: the supervisor + Portainer expect a healthcheck;
# openclaw base has none of the hassio-base plumbing, so provide our own.
HEALTHCHECK --interval=20s --timeout=10s --start-period=150s --retries=3 \
    CMD /usr/local/bin/oc-health.sh
