#!/bin/sh
# Signs Claude Code in with a claude.ai account. `claude auth login` shows a claude.ai address and
# waits for the code that page shows after the sign-in to be pasted back: the requirements loop
# publishes the address as the link input and types the pasted code. Claude Code stores the login
# itself (~/.claude/.credentials.json); this script writes nothing.
set -eu
PATH="$HOME/.local/bin:$PATH"
exec claude auth login
