#!/bin/sh
# Signs in with GitHub's device flow. Without prompts, gh prints a one-time code and
# https://github.com/login/device, which the requirements loop shows as the link input, and waits
# until the person approved it. gh stores the token in its own config, as it always does; this
# script writes nothing.
set -eu
set -- --hostname "${GHOSTDOCK_WITH_HOST:-github.com}" --web --git-protocol https
if [ -n "${GHOSTDOCK_WITH_SCOPES:-}" ]; then
  set -- "$@" --scopes "$GHOSTDOCK_WITH_SCOPES"
fi
# A linked token (GH_TOKEN) satisfies the check, so this only runs without one; unset it all the
# same, as gh refuses to store a sign-in while one is in the environment.
unset GH_TOKEN GITHUB_TOKEN
GH_PROMPT_DISABLED=1 exec gh auth login "$@"
