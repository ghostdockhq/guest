#!/usr/bin/env bash
# Validates one platform image candidate as a real Server on a Ghostdock
# instance (any instance where the ghostdock CLI is logged in; the release
# build runs it before a candidate can be promoted), and deletes the VM again.
#
#   images/validate.sh <name> <image ref, ideally by digest>
#
# <name> is an image of images/platform-images.json, which gives its VM size and the edition its
# label must name. The checks here hold for every OS image; an image's own checks are in
# images/<name>/validate.sh, sourced after them when it exists (the desktop's stream, the
# runner's unit), with the VM in $vm and this script's functions.
#
# The images are OS images: `vm up --system <ref>` boots the image
# as the VM's own system, a Server, because the image's label
# ghostdock.os=true says so (never its name). The checks run on the VM itself
# through `vm command run`, as the image's login user (ghostdock.login.user).
# The host needs an OS base of the image to boot it: a create of a digest it
# has none of has the host build it first (about 30 s, longer for the
# desktop) and waits; a create the app gave up on fails with "still
# preparing Ubuntu", and is retried for a while.
#
# Needs jq and the ghostdock CLI, logged in to the instance:
#   GHOSTDOCK_API_URL, GHOSTDOCK_ORG, GHOSTDOCK_CREDENTIALS_PATH
#   GHOSTDOCK_CLI                the command that runs the CLI (default: ghostdock)
#   GHOSTDOCK_VALIDATE_PROVIDER  host id; needed when the instance
#                                has no default host for the organization
# Exits 0 only when every check passes. Release process: images/README.md (Releases).
# The checks are shell text for the VM: its $… expand there, not here.
# shellcheck disable=SC2016
set -euo pipefail

usage="usage: validate.sh <name> <image ref>"
kind=${1:?$usage}
ref=${2:?$usage}
[ "$#" -eq 2 ] || { echo "$usage" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
entry=$(jq -c --arg kind "$kind" '.images[] | select(.name == $kind)' "$here/platform-images.json")
[ -n "$entry" ] || { echo "$kind is not an image of images/platform-images.json" >&2; exit 2; }

fail_label=$kind
# shellcheck source=images/lib/checks.sh
. "$(dirname "$0")/lib/checks.sh"

vm=""
cleanup() {
	rm -f "$run_detail"
	if [ -n "$vm" ]; then
		echo "==> deleting $vm"
		ghostdock vm delete --delete-locked "$vm" --yes >/dev/null || echo "::warning::could not delete VM $vm"
	fi
}
trap cleanup EXIT

resources=$(jq -c '.resources // {}' <<<"$entry")
# ${a[@]+"${a[@]}"}: bash before 4.4 (macOS has 3.2) calls an empty array
# unbound under set -u.
provider=()
[ -n "${GHOSTDOCK_VALIDATE_PROVIDER:-}" ] && provider=(--host "$GHOSTDOCK_VALIDATE_PROVIDER")

# Unique per run attempt, to find a VM a failed run left behind.
name="validate-$kind-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"

echo "==> creating a Server from $ref"
created=""
# The create waits while the host builds the OS base of a new digest; one
# that did not get it in time is refused as not ready yet, and one that an app
# restart cut off (vm_create_interrupted) kept nothing. Both are sent again. A create the
# connection dropped is sent again by the CLI with its idempotency key, so it
# never makes a second VM.
for attempt in $(seq 10); do
	if created=$(ghostdock vm up --json \
		--system "$ref" \
		--display-name "$name" \
		--resources "$resources" \
		--environment '{"local":[{"name":"VM_VALIDATE_PROBE","value":"ok","kind":"variable"}]}' \
		--auto-delete-days 1 \
		${provider[@]+"${provider[@]}"} 2>"$run_detail"); then
		break
	fi
	if grep -q 'still preparing' "$run_detail"; then
		echo "    the host has no OS base of it yet; waiting ($attempt)" >&2
	elif grep -qE 'vm_create_interrupted|interrupted before the VM existed' "$run_detail"; then
		# The app restarted while the host built the OS base (a deploy of the instance): nothing
		# was kept, so the create is sent again.
		echo "    the app restarted during the create; creating again ($attempt)" >&2
	else
		cat "$run_detail" >&2
		fail "create failed"
	fi
	created=""
	sleep 30
done
[ -n "$created" ] || fail "no host had an OS base of $ref after 5 minutes"
vm=$(jq -r '.vmId // .id // empty' <<<"$created")
[ -n "$vm" ] || fail "create returned no VM: $created"
echo "    VM $vm, boot $(jq -c '.boot // null' <<<"$created")"

# What boots decides what the VM is: the image's label.
status=$(ghostdock vm status "$vm" --json) || fail "vm status failed"
vm_kind=$(jq -r '.kind // empty' <<<"$status")
[ "$vm_kind" = server ] || fail "the VM is a ${vm_kind:-?}, not a Server: is the image labelled ghostdock.os=true?"
echo "ok: the image's label made a Server"
# The edition the VM card names after "Server": the ghostdock.edition label
# (none on the headless image, the default edition).
want_edition=$(jq -r '.edition // ""' <<<"$entry")
vm_edition=$(jq -r '.edition // empty' <<<"$status")
[ "$vm_edition" = "$want_edition" ] || fail "the VM's edition is '${vm_edition}', not '${want_edition}': is the image labelled ghostdock.edition?"
echo "ok: the edition is '${want_edition:-default}'"

ghostdock vm wait "$vm" --for ssh --timeout 5m || fail "no command ran on $vm within 5 minutes"

# The Server booted this build, not another OS base of the same image: a host
# without a base of the candidate's digest clones its newest one of the image,
# which would validate the wrong bits. The build writes its
# dated tag (IMAGE_VERSION) to /usr/lib/ghostdock/image-version.
name_part=${ref%%@*}
tag=""
case "${name_part##*/}" in *:*) tag=${name_part##*:} ;; esac
if [ -n "$tag" ]; then
	expect "$vm" "the Server booted this build ($tag)" "$tag" 'cat /usr/lib/ghostdock/image-version'
else
	echo "::warning::$kind: $ref names no tag; which build the Server booted is not checked"
fi

# The image's own system: one systemd, booted, nothing failed. The checks run
# as the login user, whose systemctl talks to systemd over the D-Bus system bus.
expect "$vm" "systemd is running" running 'systemctl is-system-running --wait'
expect "$vm" "no failed units" 0 'systemctl --failed --no-legend | wc -l'
# The ghostdock.login.user label: commands, SSH and the terminal land as ghost.
expect "$vm" "commands run as the login user" "ghost 1000 /home/ghost" 'echo "$(id -un) $(id -u) $HOME"'
expect "$vm" "commands start in the login user's home" /home/ghost 'pwd'
expect "$vm" "sudo needs no password" 0 'sudo -n id -u'
# The VM env, as gdo-guest writes it in an OS (/run/ghostdock).
expect "$vm" "a login shell has the VM env" ok 'bash -lc "printenv VM_VALIDATE_PROBE"'
# The ghostdock CLI: a launcher in the image, the real one installed at first use.
expect "$vm" "a login shell has the API's URL" "$GHOSTDOCK_API_URL" 'bash -lc "printenv GHOSTDOCK_API_URL"'
expect "$vm" "the ghostdock launcher is on PATH" /usr/local/bin/ghostdock 'command -v ghostdock'
expect "$vm" "ghostdock installs and runs at first use" ok \
	'ghostdock --version >/dev/null 2>&1 && gdock --version >/dev/null 2>&1 && echo ok'
expect "$vm" "ghostdock has tab completion" ok \
	'bash -c ". /usr/share/bash-completion/completions/ghostdock; _ghostdock_load_completion; declare -F __start_ghostdock >/dev/null && ghostdock __complete vm st 2>/dev/null | grep -q ^status && echo ok"'
expect "$vm" "the VM env reaches an opted-in service" ok \
	'sudo systemd-run --quiet --wait --pipe -p EnvironmentFile=/run/ghostdock/env printenv VM_VALIDATE_PROBE'
expect "$vm" "a service without EnvironmentFile has no VM env" none \
	'sudo systemd-run --quiet --wait --pipe sh -c "printenv VM_VALIDATE_PROBE || echo none"'
expect "$vm" "the env file is root only" "600 root" 'sudo stat -c "%a %U" /run/ghostdock/env'
# The OS is the user's: its own sshd, unattended upgrades, apt as on a server.
expect "$vm" "sshd listens through its socket" active 'systemctl is-active ssh.socket'
expect "$vm" "unattended-upgrades is on" enabled 'systemctl is-enabled unattended-upgrades.service'
# A package no image ships, so the install itself starts it. First the image's own
# gdo-apt-lists must be done: it fetches apt's lists right after boot, and apt-get run
# meanwhile does not wait for the lists lock, it fails ("Could not get lock").
expect "$vm" "apt's lists were fetched after boot" inactive \
	'for i in $(seq 150); do systemctl is-active --quiet gdo-apt-lists.service || break; sleep 2; done; systemctl is-active gdo-apt-lists.service || true'
expect "$vm" "apt installs and starts a service" "active 200" \
	'export DEBIAN_FRONTEND=noninteractive; sudo -E apt-get update -qq >/dev/null && sudo -E apt-get install -y -qq lighttpd >/dev/null && echo "$(systemctl is-active lighttpd) $(curl -s -o /dev/null -w "%{http_code}" http://localhost:80/)"'

# Docker is the image's own engine, at the Dockerfile's pin, reached through
# gdo-guest's proxy on /run/docker.sock; ghost is in the docker group.
engine_version=$(sed -n 's/^[[:space:]]*docker-ce=[0-9]*:\([0-9.]*\)-.*/\1/p' "$here/headless/Dockerfile")
[ -n "$engine_version" ] || fail "no docker-ce pin in images/headless/Dockerfile"
expect "$vm" "the Docker engine is the image's pin" "$engine_version $engine_version" \
	'docker version --format "{{.Client.Version}} {{.Server.Version}}"'
expect "$vm" "docker compose and buildx are there" "ok ok" \
	'echo "$(docker compose version --short >/dev/null && echo ok) $(docker buildx version >/dev/null && echo ok)"'
expect "$vm" "a container runs on the engine" ok 'docker run --rm --network none busybox:1.37 echo ok'
# The workstation's Docker API on 127.0.0.1:2375 is gone: the
# engine is reached through /run/docker.sock only.
expect "$vm" "nothing listens on the old Docker API port" 0 'ss -Hltn "sport = :2375" | wc -l'

# An OS image is a system, never a workload: its label refuses it in vm container up.
if out=$(ghostdock vm container up "$vm" --image "$ref" --json 2>&1); then
	fail "vm container up ran the OS image as a container: $out"
fi
grep -q 'is a system image' <<<"$out" || fail "vm container up of the OS image failed otherwise: $out"
echo "ok: the OS image is refused as a container"

# The image's own checks, with the VM still running.
if [ -f "$here/$kind/validate.sh" ]; then
	# shellcheck source=/dev/null
	. "$here/$kind/validate.sh"
fi

ssh=$(ghostdock vm ssh --print "$vm" --json)
jq -e '.sshCommand | test("^ssh ")' <<<"$ssh" >/dev/null || fail "no SSH command: $ssh"
echo "ok: SSH access can be minted ($(jq -r '.sshCommand | sub("^ssh [^@]+@"; "host ")' <<<"$ssh"))"
ghostdock vm ssh --revoke "$vm" >/dev/null || true

# The OS is the VM's own disk: what the user changed survives a stop and a
# start (the base image's tmpfs overlay of a Container host would lose /etc).
marker="validate-$RANDOM$RANDOM"
expect "$vm" "a marker is written to /etc and the home" ok \
	"printf %s '$marker' | sudo tee /etc/validate-marker >/dev/null && printf %s '$marker' >~/validate-marker && sync && echo ok"
echo "==> stopping and starting $vm"
ghostdock vm stop "$vm" >/dev/null || fail "stop failed"
ghostdock vm start "$vm" >/dev/null || fail "wake failed"
ghostdock vm wait "$vm" --for ssh --timeout 5m || fail "no command ran on $vm within 5 minutes of the start"
expect "$vm" "the marker survived the stop" "$marker $marker" \
	'echo "$(cat /etc/validate-marker) $(cat ~/validate-marker)"'
expect "$vm" "systemd is running after the start" running 'systemctl is-system-running --wait'

# A halt powers the Server off (images/README.md, "halt powers off"): a plain
# one stopped the kernel and left a VM that showed running and never answered.
expect "$vm" "a halt is set to power off" poweroff-force \
	'systemctl show -p SuccessAction --value systemd-halt.service'
echo "==> halting $vm"
run "$vm" 'sudo systemctl --no-block halt' >/dev/null || true
halted=""
for attempt in $(seq 30); do
	halted=$(ghostdock vm status "$vm" --json | jq -r .status)
	[ "$halted" = stopped ] && break
	sleep 2
done
[ "$halted" = stopped ] || fail "a halt left the Server ${halted:-?} after 60 s"
echo "ok: a halt stops the Server"

echo "==> $kind passed: $ref"
