# Ghostdock guest

Everything that runs inside a [Ghostdock](https://ghostdock.ai) VM, in the open: today the OS
images a Ghostdock Server boots and Ghostdock's requirement modules, later also the guest agent,
the base image and the guest kernel's configuration.

| Directory | What |
|---|---|
| [images/](images/) | The platform OS images: [headless](images/headless/), [desktop](images/desktop/) (built from the module [desktop](modules/desktop/)) and [actions-runner](images/actions-runner/), published on Docker Hub as [`ghostdockhq/*`](https://hub.docker.com/u/ghostdockhq). How they boot, what they contain, how they are built, validated and released: [images/README.md](images/README.md). |
| [modules/](modules/) | Ghostdock's requirement modules: [github-sign-in](modules/github-sign-in/), [claude-sign-in](modules/claude-sign-in/), [google-chrome](modules/google-chrome/), [claude-remote-control](modules/claude-remote-control/) and [desktop](modules/desktop/), published on Docker Hub as `ghostdockhq/module-<name>`. What they are and how versions work: [modules/README.md](modules/README.md). |

## Build your own

A Ghostdock Server can boot any image labelled `ghostdock.os=true`. Start from ours, add what
every VM of yours needs, and boot it with `ghostdock vm up --system <your image>`:

```dockerfile
FROM ghostdockhq/headless:ubuntu-26.04
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client \
 && rm -rf /var/lib/apt/lists/*
```

Values that differ per VM do not belong in the image: give them to the VM as environment
variables or systemd credentials, and let the image's units read them. See
[docs.ghostdock.ai](https://docs.ghostdock.ai).

## This repository is a copy

Ghostdock is developed in its main repository; this one is a read-only copy of the parts that run
inside a VM, updated with every change there. Issues are welcome here. A pull request here is not
merged as such: if we take it, we apply it in the main repository with you as its author, and it
arrives here with the next update.

## License

Our files, the images' and the modules', are under the [Apache License 2.0](LICENSE), which grants
no rights to the Ghostdock name or logo; each published module carries it as `LICENSE`. The images
also contain software of others under their own licenses, and the modules download software of
others when they run, under its own terms: [NOTICE](NOTICE). Security reports: [SECURITY.md](SECURITY.md).
