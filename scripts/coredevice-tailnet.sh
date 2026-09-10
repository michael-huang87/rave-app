#!/usr/bin/env bash
# Install to an iPhone that is not on this Mac's network, over Tailscale.
#
# iOS 17+ finds phones through Bonjour, which is link-local multicast and cannot cross a
# WireGuard tunnel. So this fabricates the phone's Bonjour record on the Mac and points it at
# the Mac's OWN en0 address, where socat is listening and forwarding to the phone's tailnet IP.
# remotepairingd scopes its connection to en0, which is why the record cannot simply name the
# tailnet address; it has to believe the phone is on the local wifi.
#
# Method credit: https://dev.to/kvnpt/how-to-remotely-iterate-deploy-your-sideloaded-ios-apps-over-tailnet-jak
set -euo pipefail

CONF="${COREDEVICE_TAILNET_CONF:-$HOME/.config/rave/coredevice-tailnet.conf}"
TS="${TAILSCALE_BIN:-/Applications/Tailscale.app/Contents/MacOS/Tailscale}"
AGENT="$HOME/Library/LaunchAgents/dev.rave.coredevice-tailnet.plist"
# The trusted tunnel picks a fresh port per session, reported in the 55100s. Each port costs a
# socat pair and each socat measures ~2.1MB here, so the 55000-55300 span the write-up uses is
# about 1.3GB resident. This narrower default is ~130MB. Widen it if an install cannot connect.
PORT_LO="${COREDEVICE_PORT_LO:-55100}"
PORT_HI="${COREDEVICE_PORT_HI:-55130}"

die() { echo "error: $*" >&2; exit 1; }
en0_ip() { ifconfig en0 2>/dev/null | awk '/inet /{print $2; exit}'; }

# dns-sd never exits, so every read of it is "run, wait, kill, parse".
sniff() {
    local seconds="$1"; shift
    local out; out="$(mktemp)"
    "$@" >"$out" 2>&1 &
    local pid=$!
    sleep "$seconds"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    cat "$out"; rm -f "$out"
}

cmd_capture() {
    command -v dns-sd >/dev/null || die "dns-sd missing"
    local ip; ip="$(en0_ip)" || true
    [ -n "$ip" ] || die "no en0 address; join wifi first"

    echo "Browsing for the phone's _remotepairing._tcp advertisement..."
    local browse instance
    browse="$(sniff 6 dns-sd -B _remotepairing._tcp local.)"
    instance="$(awk '/_remotepairing/ {for(i=7;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":"")} END{}' <<<"$browse" | tail -1)"
    [ -n "$instance" ] || {
        echo "$browse" >&2
        die "no phone advertising. Plug it in by USB, or put it on this wifi with Xcode's 'Connect via Network' already paired."
    }
    echo "  instance: $instance"

    local lookup host port txt
    lookup="$(sniff 6 dns-sd -L "$instance" _remotepairing._tcp local.)"
    host="$(sed -n 's/.*can be reached at \([^:]*\):.*/\1/p' <<<"$lookup" | tail -1)"
    port="$(sed -n 's/.*can be reached at [^:]*:\([0-9]*\).*/\1/p' <<<"$lookup" | tail -1)"
    txt="$(grep -oE '(identifier|authTag|ver|minVer|flags)=[^ ]*' <<<"$lookup" | tr '\n' ' ')"
    [ -n "$port" ] && [ -n "$txt" ] || { echo "$lookup" >&2; die "could not read the advertisement"; }
    echo "  host: $host port: $port"
    echo "  txt:  $txt"

    local phone
    phone="$("$TS" status --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
ios=[p for p in d.get("Peer",{}).values() if p.get("OS")=="iOS"]
print(ios[0]["TailscaleIPs"][0] if len(ios)==1 else "")' || true)"
    [ -n "$phone" ] || die "could not pick the phone off the tailnet; set PHONE_TAILNET_IP in $CONF by hand"
    echo "  phone tailnet ip: $phone"

    mkdir -p "$(dirname "$CONF")"
    cat >"$CONF" <<EOF
RP_INSTANCE='$instance'
RP_PORT='$port'
RP_HOST='$host'
RP_TXT='$txt'
PHONE_TAILNET_IP='$phone'
EOF
    echo "Saved $CONF"
}

cmd_bridge() {
    [ -f "$CONF" ] || die "no $CONF; run '$0 capture' with the phone plugged in first"
    # shellcheck disable=SC1090
    . "$CONF"
    command -v socat >/dev/null || die "socat missing; brew install socat"
    local ip; ip="$(en0_ip)"
    [ -n "$ip" ] || die "no en0 address; join wifi first"
    "$TS" status >/dev/null 2>&1 || die "tailscale is not up"

    echo "bridging $ip -> $PHONE_TAILNET_IP (ports $RP_PORT, $PORT_LO-$PORT_HI)"
    trap 'kill 0' EXIT INT TERM

    # The record must name the Mac's own en0 address: remotepairingd refuses a tunnel-scoped peer.
    # shellcheck disable=SC2086
    dns-sd -P "$RP_INSTANCE" _remotepairing._tcp local "$RP_PORT" "$RP_HOST" "$ip" $RP_TXT &

    socat TCP-LISTEN:"$RP_PORT",bind="$ip",reuseaddr,fork TCP:"$PHONE_TAILNET_IP":"$RP_PORT" &
    socat UDP-LISTEN:"$RP_PORT",bind="$ip",reuseaddr,fork UDP:"$PHONE_TAILNET_IP":"$RP_PORT" &
    for port in $(seq "$PORT_LO" "$PORT_HI"); do
        socat TCP-LISTEN:"$port",bind="$ip",reuseaddr,fork TCP:"$PHONE_TAILNET_IP":"$port" &
        socat UDP-LISTEN:"$port",bind="$ip",reuseaddr,fork UDP:"$PHONE_TAILNET_IP":"$port" &
    done
    wait
}

cmd_status() {
    local ok=0
    printf '%-28s' "socat";        command -v socat >/dev/null && echo "ok $(socat -V 2>&1 | sed -n 's/.*version \([0-9.]*\).*/\1/p' | head -1)" || { echo "MISSING (brew install socat)"; ok=1; }
    printf '%-28s' "en0 address";  local ip; ip="$(en0_ip)"; [ -n "$ip" ] && echo "ok $ip" || { echo "MISSING (join wifi)"; ok=1; }
    printf '%-28s' "tailscale";    "$TS" status >/dev/null 2>&1 && echo "ok $("$TS" ip -4 2>/dev/null | head -1)" || { echo "DOWN"; ok=1; }
    printf '%-28s' "capture file"; [ -f "$CONF" ] && echo "ok $CONF" || { echo "MISSING (run: $0 capture)"; ok=1; }
    if [ -f "$CONF" ]; then
        # shellcheck disable=SC1090
        . "$CONF"
        printf '%-28s' "phone on tailnet"
        if "$TS" status 2>/dev/null | grep -q "$PHONE_TAILNET_IP"; then echo "ok $PHONE_TAILNET_IP"; else echo "not seen"; ok=1; fi
    fi
    printf '%-28s' "bridge running"; pgrep -f "coredevice-tailnet.sh bridge" >/dev/null && echo "ok" || echo "no"
    printf '%-28s' "device state"
    # Name and Model both contain spaces, so match the state word rather than a column index.
    xcrun devicectl list devices 2>/dev/null | grep -i iPhone | head -1 \
        | grep -oE 'unavailable|available|connected|unpaired' | head -1 \
        || echo "no iPhone paired"
    return $ok
}

cmd_install_agent() {
    mkdir -p "$(dirname "$AGENT")"
    cat >"$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>dev.rave.coredevice-tailnet</string>
  <key>ProgramArguments</key>
  <array><string>$(cd "$(dirname "$0")" && pwd)/$(basename "$0")</string><string>bridge</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/coredevice-tailnet.log</string>
  <key>StandardErrorPath</key><string>/tmp/coredevice-tailnet.log</string>
</dict>
</plist>
EOF
    launchctl unload "$AGENT" 2>/dev/null || true
    launchctl load "$AGENT"
    echo "loaded $AGENT (log: /tmp/coredevice-tailnet.log)"
}

cmd_uninstall_agent() {
    launchctl unload "$AGENT" 2>/dev/null || true
    rm -f "$AGENT"
    echo "removed $AGENT"
}

case "${1:-}" in
    capture)         cmd_capture ;;
    bridge)          cmd_bridge ;;
    status)          cmd_status ;;
    install-agent)   cmd_install_agent ;;
    uninstall-agent) cmd_uninstall_agent ;;
    *) cat >&2 <<EOF
usage: $0 <command>

  capture           read the phone's Bonjour advertisement. Run ONCE with the phone
                    on USB or this wifi; it is what the bridge later replays.
  bridge            fabricate that advertisement and proxy CoreDevice to the tailnet.
                    Runs in the foreground until killed. Prefer running this only while
                    installing: it holds ~130MB of socat listeners at the default range.
  status            preflight every prerequisite.
  install-agent     run the bridge from a LaunchAgent at login. Convenient, but it pays
                    that memory all day for something used a few times a week.
  uninstall-agent   remove it.
EOF
       exit 2 ;;
esac
