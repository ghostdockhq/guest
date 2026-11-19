# syntax=docker/dockerfile:1
# actions-runner: the operating system of a VM that runs one GitHub Actions job.
# The headless OS image plus GitHub's runner and the tools a workflow takes for
# granted, so a job VM is ready at boot: nothing is installed or built per job. Like the other
# OS images it is not run as a container: the host unpacks it onto a VM's disk (an OS base) and
# the base image's os-init boots it.
#
# What is the same for every job is here. What differs per VM, the single-use runner
# registration, is a value of the VM's environment, ACTIONS_RUNNER_INPUT_JITCONFIG, which the
# runner scale set gives each job VM; actions-runner.service starts the runner only on a VM that
# has it, and powers the VM off after the job (rootfs/). The job runs as `runner`, with
# passwordless sudo and Docker, as on a GitHub-hosted runner, on the VM's own kernel: swap,
# sysctl and mounts work.
#
# Published as ghostdockhq/actions-runner. Build context: images. HEADLESS is the headless
# image of the same build, by digest (the release build passes it); the default, the
# headless candidate, is for local builds. Inputs that change only by pull request: the runner's
# release and its checksum (RUNNER_VERSION, below). Release process: images/README.md (Releases).
ARG HEADLESS=ghostdockhq/headless:ubuntu-26.04-rc

FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8 AS certs

# The runner GitHub releases, the version Ghostdock's container-based runner uses too.
# Its release notes list the checksum. Downloaded in
# a stage of its own and mounted only while it is unpacked: an ADD in the image would keep the
# 228 MB tarball in a layer even after it is deleted.
FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8 AS runner
ARG RUNNER_VERSION=2.338.2
ADD --checksum=sha256:baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40 \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    /actions-runner.tar.gz

FROM ${HEADLESS}
# Again after FROM, for the base.name label below: exactly what this build is on.
ARG HEADLESS
ARG UBUNTU_SNAPSHOT=""
ARG IMAGE_VERSION=""
ARG IMAGE_CREATED=""
ARG IMAGE_REVISION=""

# The tools a workflow takes for granted beyond the headless image (the same list as the
# Container host job runner's, GITHUB_ACTIONS_RUNNER_PACKAGES), and what the runner itself needs
# (its installdependencies.sh: ICU and friends).
RUN --mount=type=bind,from=certs,source=/etc/ssl/certs/ca-certificates.crt,target=/run/ghostdock-build/ca-certificates.crt \
    --mount=type=bind,from=runner,source=/actions-runner.tar.gz,target=/run/ghostdock-build/actions-runner.tar.gz \
    export DEBIAN_FRONTEND=noninteractive \
 && /usr/lib/ghostdock/apt-snapshot begin "${UBUNTU_SNAPSHOT}" \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential git-lfs openssl zip zstd jq \
 && install -d /home/runner \
 && tar -xzf /run/ghostdock-build/actions-runner.tar.gz -C /home/runner \
 && /home/runner/bin/installdependencies.sh \
 && /usr/lib/ghostdock/apt-snapshot end \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# runner: the user a job runs as on a GitHub-hosted runner, with its home there (an action's
# cache saved under ~ restores to the same path), passwordless sudo and the docker group.
# ghost (uid 1000) stays the login user: SSH and the terminal land as ghost.
RUN useradd --uid 1001 --home-dir /home/runner --no-create-home --shell /bin/bash --groups sudo,docker runner \
 && chown -R runner:runner /home/runner \
 && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner \
 && chmod 0440 /etc/sudoers.d/runner

COPY actions-runner/rootfs/ /
RUN systemctl enable actions-runner.service \
 # The build this OS came from, as in the headless image (images/validate.sh).
 && printf '%s\n' "${IMAGE_VERSION:-local}" >/usr/lib/ghostdock/image-version

# The last step that changes files, as in the headless image: this image changed /usr.
RUN /usr/lib/systemd/systemd-update-done

# ghostdock.os, ghostdock.login.user: from the headless image. No ghostdock.edition: the VM card
# says "Server", as for headless. ghostdock.env.*: the one value a VM of this image is given, the
# runner's single-use registration, which the runner scale set sets for each job. Not required: a
# Server of this image without it is a plain Server, and the image's validation creates one.
LABEL ghostdock.env.ACTIONS_RUNNER_INPUT_JITCONFIG.kind="secret" \
      ghostdock.env.ACTIONS_RUNNER_INPUT_JITCONFIG.title="Single-use runner registration" \
      ghostdock.env.ACTIONS_RUNNER_INPUT_JITCONFIG.description="Set by the runner scale set for each job; not meant to be entered by hand."
LABEL org.opencontainers.image.title="Ghostdock Server, Actions runner (based on Ubuntu 26.04)" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.description="Ghostdock Server OS for one GitHub Actions job, based on Ubuntu 26.04. Not affiliated with GitHub." \
      org.opencontainers.image.licenses="Apache-2.0 AND LicenseRef-Bundled-Packages" \
      org.opencontainers.image.source="https://github.com/ghostdockhq/guest/tree/main/images/actions-runner" \
      org.opencontainers.image.base.name="${HEADLESS}"
