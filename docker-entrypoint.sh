#!/bin/bash
set -e

if [ "${FLIMKIT_FLAVOUR:-web}" = "bridge" ]; then
    # The bridge answers only requests whose Host header is localhost, so reach it
    # over an SSH tunnel or with --network host rather than a published port.
    args=(--host "${FLIMKIT_BRIDGE_HOST:-0.0.0.0}" --port "${FLIMKIT_BRIDGE_PORT:-8765}")
    if [ -n "$FLIMKIT_BRIDGE_TOKEN" ]; then
        args+=(--token "$FLIMKIT_BRIDGE_TOKEN")
    fi
    echo "[flimkit] serving the bridge API; clients must send Host: localhost (SSH tunnel or --network host)" >&2
    exec flimkit-bridge "${args[@]}"
fi

export DISPLAY=:100
geometry=${FLIMKIT_GEOMETRY:-1440x900}
export FLIMKIT_WEB_PASSWORD=${FLIMKIT_WEB_PASSWORD:-$FLIMKIT_PASSWORD}

# A restart reuses the container, so /tmp keeps the lock and socket from the
# previous run and Xvfb refuses to start on a display it thinks is active.
if [ -e /tmp/.X100-lock ] && ! xdpyinfo -display :100 >/dev/null 2>&1; then
    echo "[flimkit] clearing a stale X lock from the previous run" >&2
    rm -f /tmp/.X100-lock /tmp/.X11-unix/X100
fi

# Headless X server: the Tk window runs here and the web UI drives it
Xvfb :100 -screen 0 "${geometry}x24" -nolisten tcp >/tmp/xvfb.log 2>&1 &

for i in $(seq 1 100); do
    xdpyinfo -display :100 >/dev/null 2>&1 && break
    sleep 0.2
done

# Without this the Tk window dies on a missing display and the reason is buried
if ! xdpyinfo -display :100 >/dev/null 2>&1; then
    echo "[flimkit] the X server did not start, so FLIMKit has no display to draw on:" >&2
    cat /tmp/xvfb.log >&2 2>/dev/null || true
    exit 1
fi

if [ "${FLIMKIT_DESKTOP:-0}" = "1" ] && ! command -v x11vnc >/dev/null 2>&1; then
    echo "[flimkit] FLIMKIT_DESKTOP=1 needs the desktop view, which this image does not carry. Use the 'desktop' tag." >&2
    FLIMKIT_DESKTOP=0
fi

if [ "${FLIMKIT_DESKTOP:-0}" = "1" ]; then
    # Someone can now see the desktop, so its dialogs only move to the web page while the page is in use
    export FLIMKIT_WEB_HEADLESS=0
    fluxbox >/tmp/fluxbox.log 2>&1 &
    if [ -n "$FLIMKIT_PASSWORD" ]; then
        x11vnc -storepasswd "$FLIMKIT_PASSWORD" /tmp/vncpass >/dev/null 2>&1
        auth_args=(-rfbauth /tmp/vncpass)
    else
        auth_args=(-nopw)
    fi
    x11vnc -display :100 -forever -shared -localhost -rfbport 5900 "${auth_args[@]}" -bg -o /tmp/x11vnc.log
    websockify --web=/usr/share/novnc "${FLIMKIT_DESKTOP_PORT:-14501}" localhost:5900 >/tmp/websockify.log 2>&1 &
fi

if [ -z "$FLIMKIT_WEB_PASSWORD" ]; then
    echo "[flimkit] FLIMKIT_PASSWORD is not set: anyone who can reach port ${FLIMKIT_WEB_PORT} can use FLIMKit and browse the mounted data." >&2
fi

exec flimkit
