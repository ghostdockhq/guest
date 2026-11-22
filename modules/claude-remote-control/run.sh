#!/bin/sh
# Started by systemd as the login user, in the folder (claude-remote-control.service).
# First reattaches to the session Claude Code last recorded for the folder: claude remote-control
# --continue brings one back for about four hours after the server stopped, and exits when it
# ends, or at once when there is none. Then serves new sessions. systemd starts this again when it
# exits, and after every boot.
set -u
PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
set -- --permission-mode "${CLAUDE_REMOTE_CONTROL_PERMISSION_MODE:-default}"
if [ "${CLAUDE_REMOTE_CONTROL_CHROME:-false}" = true ]; then
  set -- "$@" --chrome
fi
claude remote-control --continue "$@" || true
exec claude remote-control "$@"
