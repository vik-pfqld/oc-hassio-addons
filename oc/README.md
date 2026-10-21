# OC Stack add-on

Single mega add-on hosting the whole NAS `ai-bundle` OC stack on Home
Assistant OS: two ollama `:cloud` relays, the OpenClaw gateway, the Caddy
reverse proxy, the Claude Code sandbox (ttyd) and the warm Chromium + noVNC
scraper browser.

## Data model (zero copy)

All state stays on the **NAS md1 volume** `/volume1/Docker/ai-bundle`, exposed
to this add-on through a Home Assistant Supervisor CIFS mount named
`aibundle` → visible at `/share/docker/ai-bundle`:

| Add-on path | NAS source |
|---|---|
| `/workspace` | `ai-bundle/workspace` |
| `/app/config`, `/home/node/.openclaw` | `ai-bundle/openclaw-data` |
| `/app/workspace`, `/app/sharedworkspace` | `ai-bundle/openclaw-data/workspace`, `ai-bundle/workspace` |
| Caddy `/data` + `/config` | `ai-bundle/caddy-data`, `ai-bundle/caddy-config` |
| `/etc/caddy/Caddyfile` | derived each boot from `ai-bundle/Caddyfile` (loopback upstreams) |
| ollama `/root/.ollama` | `ai-bundle/ollama-data` / `ollama2-data` (via `$HOME` symlink) |
| Chromium profile | `ai-bundle/chrome-profile` |

Inside one container the compose aliases collapse to `127.0.0.1`:
- caddy upstreams: `ai-claudecode-web:*` → `127.0.0.1:*` (uvicorn on `18127`
  via `PT_WEB_PORT` so it doesn't collide with caddy's public `:8127` listener)
- sandbox/openclaw → `http://127.0.0.1:11434`; the ollama2 account slot reaches
  `127.0.0.1:11435` via `QUOTA_UPSTREAM_REMAP` (env-guarded shim in the quota
  proxy, no-op on the NAS copy).

## Options

| Option | Default | Meaning |
|---|---|---|
| `sandbox_enabled` | `false` | run `startup.sh` (ttyd + services + crons). **Leave off while the NAS sandbox is still the live one.** |
| `chromium_enabled` | `true` | run the bundled warm Chromium + noVNC |
| `novnc_password` | `changeme123` | VNC password for the warm-up UI on :8300 |

## Published ports

`7681` ttyd · `8127` caddy (public site) · `11434`/`11435` ollama relays ·
`9222` chromium CDP · `8300` noVNC warm-up UI.

## Rollback

Stopping this add-on and restarting the NAS containers (they are stopped, not
removed) restores the old stack; both sides share the same data on md1.