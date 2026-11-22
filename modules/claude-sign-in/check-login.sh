#!/bin/sh
# Satisfied while Claude Code is signed in with a claude.ai account whose login does not end in the
# next three days. `claude auth status` prints JSON and exits 1 when signed out.
set -eu
PATH="$HOME/.local/bin:$PATH"
status=$(claude auth status 2>/dev/null) || exit 1
printf '%s' "$status" | python3 -c '
import datetime, json, sys

status = json.load(sys.stdin)
method = status.get("authMethod")
if method != "claude.ai":
    sys.exit(f"Signed in, but not with a claude.ai account ({method}): Remote Control and Claude in Chrome need one")
end = status.get("loginExpiresAt")
if end is None:
    sys.exit(0)
if isinstance(end, (int, float)):
    ends = datetime.datetime.fromtimestamp(end / 1000 if end > 1e12 else end, datetime.timezone.utc)
else:
    ends = datetime.datetime.fromisoformat(str(end).replace("Z", "+00:00"))
if ends - datetime.datetime.now(datetime.timezone.utc) < datetime.timedelta(days=3):
    sys.exit(f"The claude.ai login ends {ends.isoformat()}: sign in again")
'
