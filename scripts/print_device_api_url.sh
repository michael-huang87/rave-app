#!/usr/bin/env bash
set -euo pipefail

PORT="${RAVE_PORT:-8000}"

if command -v tailscale >/dev/null 2>&1; then
  TS_IP="$(tailscale ip -4 2>/dev/null || true)"
else
  TS_IP=""
fi

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"

echo "Set APIBaseURL in ios/Rave/Info.plist to one of:"
if [[ -n "$TS_IP" ]]; then
  echo "  http://${TS_IP}:${PORT}   (Tailscale — works at home and away)"
fi
if [[ -n "$LAN_IP" ]]; then
  echo "  http://${LAN_IP}:${PORT}   (home Wi‑Fi only)"
fi
if [[ -z "$TS_IP" && -z "$LAN_IP" ]]; then
  echo "  (no Tailscale or LAN IP found — install Tailscale and sign in first)"
fi
