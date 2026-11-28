#!/usr/bin/env bash
# Boots a platform image as a Server the way a Docker host or an Incus host does, in a system
# container, and checks that its systemd comes up with no failed unit. validate.sh
# boots it on Ghostdock Cloud, a microVM: units that behave differently in a container
# (ConditionVirtualization=, no /dev/ptp0, no kernel modules, no clock to set) are only seen here.
# chrony-wait.service was one (#1950).
#
#   validate-container.sh docker|incus <image ref> <host image ref>
#
# <host image ref> is a Docker host release (ghostdockhq/host@sha256:…): its platform tree
# (/usr/lib/ghostdock/platform: gdo-guest, the OS units and generators) is what a real host
# binds into a Server. The container gets what the host gives it (dockervm/shape.go osVM,
# incusvm/shape.go Instance) except the host side: no gdo-guest socket peer and no network, so
# gdo-guest waits for its host as on a host that is not connected yet.
#
# Needs: docker (and sysbox-runc for docker), or incus (an initialised one) for incus. Runs as
# root (the Incus leg's disk devices are owned by it). Removes its container and files at the end, also after a failure.
set -euo pipefail

mode=${1:-} ref=${2:-} host=${3:-}
case $mode in docker | incus) ;; *) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac
[ -n "$ref" ] && [ -n "$host" ] || { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

name=gdo-validate-$mode-$$
work=$(mktemp -d)
cleanup() {
	if [ "$mode" = docker ]; then
		docker rm -f "$name" >/dev/null 2>&1 || true
	else
		incus delete -f "$name" >/dev/null 2>&1 || true
		incus image delete "$name" >/dev/null 2>&1 || true
	fi
	sudo rm -rf "$work" 2>/dev/null || rm -rf "$work"
}
trap cleanup EXIT
fail() {
	echo "::error::$mode: $*" >&2
	exit 1
}

# The platform tree, from the host release as a real host has it.
c=$(docker create "$host" true)
docker cp "$c:/usr/lib/ghostdock/platform" "$work/platform" >/dev/null
docker rm "$c" >/dev/null
p=$work/platform
[ -x "$p/usr/lib/gdo/os/gdo-os-generator" ] || fail "$host has no platform tree (usr/lib/gdo/os/gdo-os-generator)"
mkdir -p "$work/guest" "$work/data" "$work/docker" "$work/containerd"
# The network file a Docker host writes (dockervm GuestNetworkText); nothing answers at its gateway.
echo "gdo.ip=10.250.0.2/30 gdo.gw=10.250.0.1 gdo.ll6=fe80::2" >"$work/guest/network"
echo "nameserver 127.0.0.1" >"$work/resolv.conf"

run() { # run <command>: in the Server, as root
	if [ "$mode" = docker ]; then
		docker exec "$name" sh -c "$1"
	else
		incus exec "$name" -- sh -c "$1"
	fi
}

if [ "$mode" = docker ]; then
	# dockervm/shape.go osVM, without the host's network, cgroup parent and volumes.
	docker run -d --name "$name" --runtime=sysbox-runc --entrypoint /sbin/init \
		--stop-signal SIGRTMIN+3 --hostname validate --network none \
		--device /dev/fuse --device /dev/net/tun --memory 4g --memory-swap 4g \
		-v "$work/docker:/var/lib/docker" -v "$work/containerd:/var/lib/containerd" \
		-v "$work/data:/mnt/host" -v "$work/guest:/run/gdo-host" \
		-v "$work/resolv.conf:/etc/resolv.conf:ro" \
		-v "$p:/run/gdo/base:ro" \
		-v "$p/usr/lib/gdo/os/gdo-os-generator:/run/systemd/system-generators/gdo-os:ro" \
		"$ref" >/dev/null
else
	# incusvm/image.go: through Incus's OCI remote, then a system image (no "type").
	incus remote list -f csv | grep -q '^gdo-oci-docker,' ||
		incus remote add gdo-oci-docker https://docker.io --protocol=oci --public >/dev/null
	incus image copy "gdo-oci-docker:${ref#docker.io/}" local: --alias "$name" >/dev/null
	incus image show "$name" | sed '/^  type:/d' | incus image edit "$name"
	# incusvm/shape.go Instance: unprivileged, nesting, the platform and guest folders at
	# /dev/.ghostdock (systemd's tmpfs on /run would hide them), the wrapper generator.
	incus init "$name" "$name" -c security.nesting=true -c limits.memory=4GiB \
		-c linux.sysctl.net.ipv4.ping_group_range="0 65535" >/dev/null
	incus config device add "$name" gdo-guest disk source="$work/guest" path=/dev/.ghostdock/host shift=true >/dev/null
	incus config device add "$name" gdo-data disk source="$work/data" path=/mnt/host shift=true >/dev/null
	incus config device add "$name" gdo-platform disk source="$p" path=/dev/.ghostdock/base readonly=true shift=true >/dev/null
	incus config device add "$name" gdo-generator disk source="$p/usr/lib/gdo/incus/gdo-incus-generator" \
		path=/etc/systemd/system-generators/gdo-os readonly=true shift=true >/dev/null
	incus start "$name"
fi

# systemd settles: running, or degraded with the failed units named. Not "starting" after 4
# minutes either: a unit that waits for something a container never gets (chrony-wait waited 3
# minutes for a chronyd that is skipped in a container, #1950) is named among the queued jobs.
logs() { # the container's console: what init said before systemd's bus was up
	if [ "$mode" = docker ]; then
		docker ps -a --filter "name=^$name$" --format 'container: {{.Status}}'
		docker logs --tail 80 "$name" 2>&1
	else
		incus list "$name" -f csv -c ns
		incus console "$name" --show-log 2>&1 | tail -80
	fi
}
up=
for _ in $(seq 90); do
	if run 'test -S /run/systemd/private' >/dev/null 2>&1; then up=1; break; fi
	sleep 1
done
[ -n "$up" ] || { logs; fail "systemd did not start within 90 s"; }
state=$(run 'timeout 240 systemctl is-system-running --wait' 2>/dev/null || true)
echo "$mode: systemd is $state"
failed=$(run 'systemctl --failed --no-legend --plain | cut -d" " -f1' || true)
jobs=$(run 'systemctl list-jobs --no-legend --plain' || true)
if [ -n "$failed" ] || [ "$state" != running ]; then
	for u in $failed; do
		echo "--- $u"
		run "systemctl status --no-pager -n 30 '$u'" || true
	done
	[ -z "$jobs" ] || { echo "--- jobs still queued"; echo "$jobs"; }
	[ -n "$failed" ] || logs
	fail "systemd is ${state:-unknown}; failed units: $(echo $failed)"
fi
echo "$mode: no failed unit"
