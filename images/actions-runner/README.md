# actions-runner

The operating system of a VM that runs one GitHub Actions job:
the [headless](../headless/) image plus GitHub's runner and the tools a workflow takes for granted,
published as `ghostdockhq/actions-runner` with the same tags as the other platform images.

| | |
|---|---|
| Runner | GitHub's release `RUNNER_VERSION` in the [Dockerfile](Dockerfile), by checksum, in `/home/runner` |
| Tools beyond headless | `build-essential git-lfs openssl zip zstd jq`, and what the runner's `installdependencies.sh` adds |
| The job's user | `runner` (uid 1001), home `/home/runner`, passwordless sudo, in `docker`; `ghost` stays the login user |
| Per VM | only `ACTIONS_RUNNER_INPUT_JITCONFIG` in the VM's environment, the single-use registration the runner scale set gives each job VM |

**How a job runs.** [`actions-runner.service`](rootfs/etc/systemd/system/actions-runner.service) is enabled. At boot,
after gdo-guest has applied the host's first config (`/run/ghostdock/env` is there), it reads the VM env and:

- without `ACTIONS_RUNNER_INPUT_JITCONFIG`, is skipped (`ExecCondition`; `Result=exec-condition`, not failed) and
  the VM stays up as a plain Server;
- with it, runs `run.sh`, which takes the registration, runs one job and exits. Then
  [`actions-runner-done`](rootfs/usr/lib/ghostdock/actions-runner-done) powers the VM off, and an ephemeral VM is deleted.

The job has the VM's own kernel and root: `swapon` on a swapfile, `sysctl` and mounts work, unlike in a Container
host's runner container. The image holds no platform software and nothing per VM, so one build serves every
organization and every job. Build your own on it (`FROM ghostdockhq/actions-runner`) for more tools.

[`validate.sh`](validate.sh) holds its own checks (the runner's release, the user, the skipped unit, a
swapfile); [images/validate.sh](../validate.sh) runs them after the checks every OS image has.
