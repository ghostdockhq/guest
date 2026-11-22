# Ghostdock's requirement modules

The requirement modules Ghostdock publishes: sets of requirements and the scripts they run,
which a template names in `uses` (`ghostdock/<name>@1`) and every VM made from it keeps true.
The module format, how modules are used, pinned and published:
[docs.ghostdock.ai/vms/modules](https://docs.ghostdock.ai/vms/modules).

| Module | Does |
|---|---|
| [github-sign-in](github-sign-in/) | Installs GitHub's `gh`, signs the VM's login user in with a code on github.com, and makes `git` use it. |
| [claude-sign-in](claude-sign-in/) | Installs Claude Code for the login user and signs it in with a claude.ai account. |
| [google-chrome](google-chrome/) | Installs Google Chrome from Google, once a person accepts its terms. |
| [claude-remote-control](claude-remote-control/) | Runs `claude remote-control` in a folder as a service of the login user. |

**Where they are published.** Each folder is published to Docker Hub as an OCI artifact,
`ghostdockhq/module-<name>`, tagged with the `release` in its `module.yaml` (`1.0.0`). Each
artifact carries this folder, the Apache License 2.0 as `LICENSE`, and the annotations
`org.opencontainers.image.source` (its folder here), `org.opencontainers.image.version`,
`org.opencontainers.image.licenses` (`Apache-2.0`) and `org.opencontainers.image.vendor`.

**A published version never changes.** A change to a module ships as a new release: a fix as
`1.0.1`, a new optional value as `1.1.0`, a change that breaks templates as `2.0.0`. A template that
says `@1` picks the highest `1.x.y` the next time it is saved.

**Reviewed.** Every change to these modules is reviewed before it is published, and Ghostdock
marks them Curated.

**What they download.** The modules contain no one else's software. When they run on a VM, they
download it from its maker, each under its own terms: [NOTICE](../NOTICE).
