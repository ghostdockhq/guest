# actions-runner

The operating system of a VM that runs one GitHub Actions job:
the [headless](../headless/) image plus GitHub's runner and the tools a workflow takes for granted,
published as `ghostdockhq/actions-runner` with the same tags as the other platform images.

| | |
|---|---|
| Runner | GitHub's release `RUNNER_VERSION` in the [Dockerfile](Dockerfile), by checksum, in `/home/runner` |
| apt | The package lists ship in the image, fetched from the live archive at build, so the first boot fetches none and a job's `apt-get install` works at once (lists as old as the build, as on a GitHub-hosted runner; `apt-get update` refreshes them); `apt-daily.timer` and `apt-daily-upgrade.timer` are masked, as a job VM lives for one job |
| Docker | The runner starts beside dockerd, not after it; its job-started hook ([`actions-runner-wait-docker`](rootfs/usr/lib/ghostdock/actions-runner-wait-docker), shown as the job's "Set up runner" step) waits until Docker answers, at most a minute, before the first step |
| Tools beyond headless | `build-essential git-lfs openssl zip zstd jq`, Node.js and npm (with `node-gyp`), `gh`, `python` (with pip, venv and pipx), `skopeo`, and what the runner's `installdependencies.sh` adds |
| The job's user | `runner` (uid 1001), home `/home/runner`, passwordless sudo, in `docker`; `ghost` stays the login user |
| Per VM | only `ACTIONS_RUNNER_INPUT_JITCONFIG` in the VM's environment, the single-use registration the runner scale set gives each job VM |

**How a job runs.** [`actions-runner.service`](rootfs/etc/systemd/system/actions-runner.service) is enabled. At boot,
after gdo-guest has applied the host's first config (`/run/ghostdock/env` is there), it reads the VM env and:

- without `ACTIONS_RUNNER_INPUT_JITCONFIG`, is skipped (`ExecCondition`; `Result=exec-condition`, not failed) and
  the VM stays up as a plain Server;
- [`actions-runner.path`](rootfs/etc/systemd/system/actions-runner.path) starts it again whenever gdo-guest writes
  `/run/ghostdock/env` (every config push), so a registration that arrives after the boot's start (gdo-guest
  restarted, or the host's first config came late) still runs the job instead of leaving the VM idle;
- runs at most once per boot: its first start leaves `/run/actions-runner.started`, and a later start (a config
  push between the job's end and the poweroff) is skipped, so the VM itself keeps it to one job;
- with it, runs `run.sh`, which takes the registration, runs one job and exits. Then
  [`actions-runner-done`](rootfs/usr/lib/ghostdock/actions-runner-done) powers the VM off, and an ephemeral VM is deleted.

The job has the VM's own kernel and root: `swapon` on a swapfile, `sysctl` and mounts work, unlike in a Container
host's runner container. The image holds no platform software and nothing per VM, so one build serves every
organization and every job. Build your own on it (`FROM ghostdockhq/actions-runner`) for more tools.

[`validate.sh`](validate.sh) holds its own checks (the runner's release, the user, the skipped unit, a
swapfile); [images/validate.sh](../validate.sh) runs them after the checks every OS image has.
