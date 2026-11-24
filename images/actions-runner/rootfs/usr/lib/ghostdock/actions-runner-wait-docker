#!/bin/sh
# The runner's job-started hook (ACTIONS_RUNNER_HOOK_JOB_STARTED, actions-runner.service): waits
# until Docker answers before the job's first step, at most a minute. The runner starts beside
# dockerd rather than after it, which saves its 1-3 s on the way to every job; a job assigned
# before dockerd is up waits here instead. It never fails the job: an image or VM without Docker
# goes on, as it would have.
command -v docker >/dev/null || exit 0
i=0
while [ "$i" -lt 120 ]; do
	docker version >/dev/null 2>&1 && exit 0
	systemctl is-failed --quiet docker.service && exit 0
	sleep 0.5
	i=$((i + 1))
done
echo "Docker did not answer within a minute; the job goes on without waiting." >&2
exit 0
