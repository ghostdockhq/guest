# shellcheck shell=bash
# Test helpers for scripts that drive a Ghostdock instance through the
# ghostdock CLI, the way a user does: images/validate.sh, and any test of a
# Ghostdock instance. Source it after `set -euo pipefail`:
#
#   . "$(dirname "$0")/lib/checks.sh"
#
# The CLI itself retries what a redeploy of the app answers (5xx, dropped
# connections) for reads and for calls with an idempotency key, waits with
# `vm wait`, and follows a command to its end with `vm command run --wait`;
# these helpers only check results.
#
# Needs jq and the CLI, logged in to the instance:
#   GHOSTDOCK_API_URL, GHOSTDOCK_ORG, GHOSTDOCK_CREDENTIALS_PATH
#   GHOSTDOCK_CLI  the command that runs the CLI (default: ghostdock)
#
# The caller sets fail_label (the prefix of every ::error::) and removes
# $run_detail in its EXIT trap.

read -r -a cli_cmd <<<"${GHOSTDOCK_CLI:-ghostdock}"
[ "${#cli_cmd[@]}" -gt 0 ] || { echo "GHOSTDOCK_CLI names no command" >&2; exit 2; }

# ghostdock <args>: the CLI that GHOSTDOCK_CLI names, so the scripts read
# like the commands a user types.
ghostdock() {
	"${cli_cmd[@]}" "$@"
}

fail_label=${fail_label:-}
run_detail=$(mktemp)

# To stderr: a fail inside run, which is called in $(…), would otherwise
# end up in the caller's captured output instead of the log.
fail() {
	echo "::error::${fail_label:+$fail_label: }$*" >&2
	exit 1
}

# now_ms: wall clock in milliseconds. EPOCHREALTIME is bash 5; macOS ships
# 3.2, where perl stands in.
now_ms() {
	if [ -n "${EPOCHREALTIME:-}" ]; then
		local t=${EPOCHREALTIME/,/.}
		echo $((${t%.*} * 1000 + 10#$(printf '%.3s' "${t#*.}")))
	else
		perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'
	fi
}

# run <vm> <shell command>: runs it on the VM as its login user (ghost): on
# a Server the VM itself, on a Container host its one running container,
# until it ends. Prints its stdout and returns its exit code.
run() {
	local out rc=0
	out=$(ghostdock vm command run "$1" --command "$2" --wait --json) || rc=$?
	# Everything but stdout, for expect's error message: a status other than
	# completed, the exit code and stderr say why a command failed.
	jq -c '{status, exitCode, stderr: ((.stderr // "") | .[-600:]), error: (.error.message // null)}' <<<"$out" >"$run_detail" 2>/dev/null ||
		printf '%s' "$out" | head -c 600 >"$run_detail"
	jq -r '.stdout // ""' <<<"$out" 2>/dev/null || true
	return "$rc"
}

# expect <vm> <description> <expected stdout> <shell command>
expect() {
	local got
	got=$(run "$1" "$4") || fail "$2: exit code $? (output: ${got:-none}; $(cat "$run_detail" 2>/dev/null))"
	got=$(printf '%s' "$got" | tr -d '\r' | sed -e 's/[[:space:]]*$//')
	[ "$got" = "$3" ] || fail "$2: want '$3', got '$got'"
	echo "ok: $2"
}
