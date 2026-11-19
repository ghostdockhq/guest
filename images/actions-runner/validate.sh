# The runner image's own checks, sourced by images/validate.sh after the checks every OS image
# has, with the VM in $vm and that script's functions (expect, run, fail, and ghostdock). The VM has no
# runner registration (ACTIONS_RUNNER_INPUT_JITCONFIG), so the runner must be skipped and the VM
# stay up; a real job is the runner scale set's to start.
# The checks are shell text for the VM: its $… expand there, not here.
# shellcheck shell=bash disable=SC2016,SC2154

runner_version=$(sed -n 's/^ARG RUNNER_VERSION=//p' "$here/actions-runner/Dockerfile")
[ -n "$runner_version" ] || fail "no RUNNER_VERSION in images/actions-runner/Dockerfile"
# As runner, as a job runs it: the runner writes its _diag folder in runner's home.
expect "$vm" "the runner is the Dockerfile's release" "$runner_version" \
	'sudo -u runner -H /home/runner/bin/Runner.Listener --version'
# Node.js and npm's node-gyp, as on a GitHub-hosted runner: native modules build in a job.
expect "$vm" "Node.js and node-gyp are there" ok \
	'sudo -u runner -H sh -c "node --version >/dev/null && npm --version >/dev/null && command -v node-gyp >/dev/null || ls /usr/share/nodejs/node-gyp >/dev/null" && echo ok'
# A job runs as runner, as on a GitHub-hosted runner: its home, sudo without a password, Docker.
expect "$vm" "jobs run as runner, in sudo and docker" "runner 1001 /home/runner docker sudo" \
	'echo "$(id -un runner) $(id -u runner) $(getent passwd runner | cut -d: -f6) $(id -nG runner | tr " " "\n" | grep -xE "docker|sudo" | sort | paste -sd " ")"'
expect "$vm" "runner's sudo needs no password" 0 'sudo -u runner sudo -n id -u'
expect "$vm" "runner reaches Docker without sudo" ok \
	'sudo -u runner docker run --rm --network none busybox:1.37 echo ok'
# Without a registration the unit is skipped (ExecCondition), not failed, and nothing powers off.
expect "$vm" "the runner unit is enabled" enabled 'systemctl is-enabled actions-runner.service'
expect "$vm" "without a registration the runner is skipped" exec-condition \
	'systemctl show -p Result --value actions-runner.service'
expect "$vm" "a skipped runner does not power the VM off" "0 running" \
	'sudo SERVICE_RESULT=exec-condition /usr/lib/ghostdock/actions-runner-done; echo "$? $(systemctl is-system-running)"'
# Why jobs run on a Server and not in a container: the VM's own kernel and root.
expect "$vm" "a job can add swap" /swapfile \
	'sudo fallocate -l 256M /swapfile && sudo chmod 600 /swapfile && sudo mkswap -q /swapfile && sudo swapon /swapfile && swapon --show=NAME --noheadings; sudo swapoff /swapfile; sudo rm -f /swapfile'
