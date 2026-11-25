#!/bin/sh
# Started by systemd as the login user, in the folder (claude-remote-control.service), after every
# boot and whenever it exits. Plain `claude remote-control` brings back every session the server
# served before it stopped (for about four hours after; code.claude.com/docs/en/remote-control),
# then serves new ones. Not --continue: that serves the one session it brings back and exits when
# it ends. --spawn same-dir answers the spawn-mode question a service cannot answer; serve.py
# answers the one-time "Enable Remote Control?" and waits out a login claude.ai refused.
set -u
PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
set -- --spawn same-dir --permission-mode "${CLAUDE_REMOTE_CONTROL_PERMISSION_MODE:-default}"
if [ "${CLAUDE_REMOTE_CONTROL_CHROME:-false}" = true ]; then
  set -- "$@" --chrome
  # Claude in Chrome uses the Chrome on the VM's desktop: its display, and the login user's
  # session bus when the desktop runs as this user (/etc/ghostdock/desktop.env on a desktop).
  if [ -r /etc/ghostdock/desktop.env ]; then
    DISPLAY=$(sed -n 's/^DISPLAY=//p' /etc/ghostdock/desktop.env)
    XAUTHORITY=$(sed -n 's/^XAUTHORITY=//p' /etc/ghostdock/desktop.env)
    export DISPLAY XAUTHORITY
    runtime=/run/user/$(id -u)
    if [ -d "$runtime" ]; then
      export XDG_RUNTIME_DIR="$runtime"
      [ -S "$runtime/bus" ] && export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus"
    fi
  fi
fi
exec python3 "$(dirname "$0")/serve.py" "$@"
