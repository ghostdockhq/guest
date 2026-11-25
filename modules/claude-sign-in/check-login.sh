#!/bin/sh
# Satisfied while Claude Code is signed in with a claude.ai account whose login neither ends soon
# nor was refused by claude.ai.
#
# - `claude auth status` prints JSON and exits 1 when signed out. Its loginExpiresAt is the login's
#   latest expected end; `claude auth status --text` says the earlier one ("Sign-in ends: between
#   2026-11-20 and 2026-11-23 (…)", or "any day now" / "may have ended"). Use does not extend a
#   login, so this asks for a new sign-in a day before the earlier end, and four days before
#   loginExpiresAt when the text names no earlier one.
# - A revoked login still reads as signed in on disk. Whatever sees claude.ai refuse it (the
#   claude-remote-control service does) writes ~/.claude/ghostdock/login-rejected; it counts until
#   a sign-in writes a newer ~/.claude/.credentials.json (sign-in.sh also removes it).
set -eu
PATH="$HOME/.local/bin:$PATH"
status=$(claude auth status 2>/dev/null) || {
  echo "Claude Code is not signed in" >&2
  exit 1
}
text=$(claude auth status --text 2>/dev/null || true)
STATUS=$status TEXT=$text python3 - <<'EOF'
import datetime, json, os, re, sys

UTC = datetime.timezone.utc
now = datetime.datetime.now(UTC)
home = os.path.expanduser("~")

status = json.loads(os.environ["STATUS"])
method = status.get("authMethod")
if method != "claude.ai":
    sys.exit(f"Signed in, but not with a claude.ai account ({method}): Remote Control and Claude in Chrome need one")

marker = os.path.join(home, ".claude", "ghostdock", "login-rejected")
credentials = os.path.join(home, ".claude", ".credentials.json")
if os.path.exists(marker):
    signed_in_since = os.path.getmtime(credentials) if os.path.exists(credentials) else 0
    if os.path.getmtime(marker) >= signed_in_since:
        with open(marker) as f:
            said = f.read().strip()[:200]
        sys.exit("claude.ai refused this VM's login" + (f" ({said})" if said else "") + ": sign in again")


def when(value):
    if isinstance(value, (int, float)):
        return datetime.datetime.fromtimestamp(value / 1000 if value > 1e12 else value, UTC)
    parsed = datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


text = os.environ.get("TEXT", "")
line = next((l for l in text.splitlines() if l.strip().lower().startswith("sign-in")), "")
if re.search(r"any day now|may have ended", line):
    sys.exit(f"The claude.ai login ends any day now ({line.strip()}): sign in again")
between = re.search(r"between (\d{4}-\d{2}-\d{2}) and", line)
if between:
    earlier = when(between.group(1))
    if earlier - now < datetime.timedelta(days=1):
        sys.exit(f"The claude.ai login may end from {earlier.date()}: sign in again")
end = status.get("loginExpiresAt")
if end is not None and when(end) - now < datetime.timedelta(days=4):
    sys.exit(f"The claude.ai login ends by {when(end).isoformat()}: sign in again")
EOF
