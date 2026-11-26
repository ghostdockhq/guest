# syntax=docker/dockerfile:1
# headless: the operating system of a Ghostdock VM. Ubuntu with
# systemd, sshd and Docker's engine, as on a cloud VM. It is not run as a
# container: the host unpacks the image's filesystem onto a VM's disk (an OS
# base) and the base image's os-init boots it, with the host's kernel and the
# platform's gdo-guest from the base image. Built as a Docker image for the
# release pipeline (snapshot pinning, validation as a real VM, promotion).
#
# Build context: images (the family's LICENSE lives there).
# Inputs that change only by pull request: the base image digest below and
# the CA bundle image. UBUNTU_SNAPSHOT is the archive snapshot the packages
# come from (snapshot.ubuntu.com); the weekly build moves it to its own date,
# so one date and one digest give the same packages. IMAGE_VERSION,
# IMAGE_CREATED and IMAGE_REVISION are the OCI labels (the published tag,
# the snapshot's moment and the git commit; the release build passes
# them). Release process: images/README.md (Releases).

# The CA bundle for apt's HTTPS to the snapshot service; mounted only while
# apt runs, so the image gets its own from the snapshot.
FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8 AS certs

FROM ubuntu:26.04@sha256:f144425ff09be612d6d9ad965196e9cdc23dae1f42110a8a11a3e9a8198759f7

# yyyymmddThhmmssZ. Empty uses the live archive (local builds; there is no
# snapshot of ubuntu-ports, so an arm64 build always uses the live archive).
ARG UBUNTU_SNAPSHOT=""
# The OCI labels below; empty for local builds.
ARG IMAGE_VERSION=""
ARG IMAGE_CREATED=""
ARG IMAGE_REVISION=""

# No ENV: the image is unpacked, not run, so only files count (the locale is
# /etc/default/locale).

COPY headless/rootfs/usr/lib/ghostdock/apt-snapshot /usr/lib/ghostdock/apt-snapshot

# Storage tools of a standard Ubuntu server (ubuntu-server depends on lvm2, mdadm, xfsprogs and
# btrfs-progs; cryptsetup comes with every server install), so a VM behaves like a standard VPS:
# the VM's kernel has their drivers. thin-provisioning-tools is lvm2's recommend
# for thin pools, which --no-install-recommends would skip. Not multipath-tools or open-iscsi
# (SAN tooling a VM has no use for), not snapd.
#
# System and hardware tools of ubuntu-standard, so the usual first commands on a new server work:
# pciutils (lspci), usbutils (lsusb), dmidecode, lshw, ethtool, hdparm, parted, dosfstools,
# ntfs-3g, numactl, sysstat (sar, iostat), trace-cmd, bcache-tools (ubuntu-server; the kernel has
# bcache) and util-linux-extra (hwclock). About 14 MB. Compared 2026-11-26 with ubuntu-minimal,
# ubuntu-standard and ubuntu-server 26.04; what of theirs stays out, and why:
# https://docs.ghostdock.ai/vms/ubuntu-differences
#
# apparmor: Ubuntu's profiles load at boot (apparmor.service) and Docker confines every container
# with docker-default, as on an Ubuntu server; the VM's kernel has AppArmor. Unprivileged user
# namespaces stay open: the kernel has no Ubuntu userns restriction.
#
# Docker's engine with the Compose and buildx plugins, from Docker's apt
# repository, as Docker documents it for Ubuntu servers. Docker's repository
# has no snapshots: the exact versions are the image's pin, so one build
# input gives one image. After the create, apt updates Docker like every
# other package: the image keeps Docker's source and key
# (/etc/apt/keyrings/docker.asc, vendored here as docker.asc, the base
# image's key, accepted only with the fingerprint of base-image/pins.env;
# images/check-docker-pins.sh checks both).
RUN --mount=type=bind,from=certs,source=/etc/ssl/certs/ca-certificates.crt,target=/run/ghostdock-build/ca-certificates.crt \
    --mount=type=bind,source=docker.asc,target=/run/ghostdock-build/docker.asc \
    export DEBIAN_FRONTEND=noninteractive \
 && /usr/lib/ghostdock/apt-snapshot begin "${UBUNTU_SNAPSHOT}" \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus udev \
      openssh-server crun unattended-upgrades \
      sudo ca-certificates curl wget gnupg \
      vim-tiny nano less bash-completion \
      iproute2 iputils-ping dnsutils netcat-openbsd \
      procps psmisc htop lsof \
      git openssh-client rsync unzip xz-utils \
      locales tzdata \
      python3 whiptail debconf-i18n logrotate lsb-release \
      libpam-systemd libnss-systemd dbus-user-session \
      command-not-found unminimize \
      file strace time bsdextrautils xxd uuid-runtime gettext-base cpio ed patch \
      iputils-tracepath mtr-tiny inetutils-telnet tcpdump tmux screen \
      kmod \
      lvm2 thin-provisioning-tools mdadm xfsprogs btrfs-progs cryptsetup \
      pciutils usbutils dmidecode lshw ethtool hdparm parted dosfstools ntfs-3g numactl \
      sysstat trace-cmd bcache-tools util-linux-extra \
      apparmor \
 && gnupg_home=$(mktemp -d) \
 && fpr=$(GNUPGHOME="$gnupg_home" gpg --batch --show-keys --with-colons /run/ghostdock-build/docker.asc 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }') \
 && rm -rf "$gnupg_home" \
 && if [ "$fpr" != 9DC858229FC7DD38854AE2D88D81803C0EBFCD88 ]; then echo "docker.asc fingerprint '$fpr', want 9DC858229FC7DD38854AE2D88D81803C0EBFCD88" >&2; exit 1; fi \
 && printf '%s\n' \
      'Types: deb' \
      'URIs: https://download.docker.com/linux/ubuntu' \
      'Suites: resolute' \
      'Components: stable' \
      "Architectures: $(dpkg --print-architecture)" \
      'Signed-By: /etc/apt/keyrings/docker.asc' \
      >/etc/apt/sources.list.d/docker.sources \
 && install -D -m 0644 /run/ghostdock-build/docker.asc /etc/apt/keyrings/docker.asc \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      docker-ce=5:29.8.1-1~ubuntu.26.04~resolute \
      docker-ce-cli=5:29.8.1-1~ubuntu.26.04~resolute \
      containerd.io=2.3.6-1~ubuntu.26.04~resolute \
      docker-compose-plugin=5.5.1-1~ubuntu.26.04~resolute \
      docker-buildx-plugin=0.37.1-1~ubuntu.26.04~resolute \
 && /usr/lib/ghostdock/apt-snapshot end \
 && locale-gen en_US.UTF-8 \
 && update-locale LANG=en_US.UTF-8 \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 # Of the base image's apt and dpkg settings for image builds, these would
 # make the VM's apt differ from a server's: no periodic list updates
 # (apt.conf.d/10periodic turns them on), dpkg without fsync and a different
 # autoremove. The others stay, as they keep apt's files on each VM at about
 # 45 MB instead of 255 MB: no binary package cache (docker-clean; each apt
 # command takes about 0.8 s longer), compressed lists (docker-gzip-indexes)
 # and no long package descriptions (docker-no-languages; apt show prints
 # the one-line summary).
 && rm /etc/apt/apt.conf.d/docker-disable-periodic-update /etc/dpkg/dpkg.cfg.d/docker-apt-speedup \
      /etc/apt/apt.conf.d/docker-autoremove-suggests

# The VM's network, DNS and clock are gdo-guest's: it
# configures eth0 from the kernel command line and writes resolv.conf, and the
# host keeps the clock. Consoles stay off (no password to log in with; the
# console log is the host's), and so do the kernel's module loader (the
# kernel loads no module, and this root ships no .ko) and e2scrub (no LVM
# inside). kmod stays: the platform's generator mounts the kernel's index of
# built-in drivers at /usr/lib/modules/<release>, so `modprobe br_netfilter`
# (k3s, installers) finds the driver built in and succeeds without a load. systemd-firstboot would ask on the console at the first boot of
# every VM. The container-only journald generator and sys-kernel mount
# conditions live in rootfs/; they do nothing on a microVM.
RUN systemctl mask \
      getty.target console-getty.service serial-getty@ttyS0.service \
      systemd-modules-load.service \
      systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service \
      systemd-networkd-varlink.socket systemd-networkd-resolve-hook.socket \
      systemd-resolved.service systemd-timesyncd.service \
      systemd-firstboot.service \
      e2scrub_all.timer e2scrub_all.service e2scrub_reap.service \
 && systemctl set-default multi-user.target

# The login user, as on a cloud VM: SSH, the web terminal and commands land
# as ghost (the ghostdock.login.user label below), sudo needs no password,
# and docker needs no sudo (the docker group, as Docker's post-install steps
# say). Ubuntu's image comes with `ubuntu` on uid 1000; ghost takes its place.
# The app's file tools write as ghost too, into its home.
RUN userdel --remove ubuntu 2>/dev/null || true \
 && useradd --create-home --uid 1000 --shell /bin/bash --groups sudo,docker ghost \
 && echo 'ghost ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ghost \
 && chmod 0440 /etc/sudoers.d/ghost

COPY headless/rootfs/ /
COPY LICENSE NOTICE /usr/share/doc/ghostdock/
RUN systemctl enable gdo-apt-lists.service \
 # Every VM gets its own machine-id and SSH host keys on its first boot (no
 # machine-id is a first boot; sshd-keygen.service makes the keys then).
 && rm -f /etc/machine-id /var/lib/dbus/machine-id /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub \
 # The base image's policy-rc.d keeps apt from starting services; here
 # `apt install nginx` should leave nginx running, as on a VM.
 && rm -f /usr/sbin/policy-rc.d \
 # The build this OS came from (the dated tag; "local" for a local build):
 # the image's labels are not on the disk it is unpacked to, and
 # images/validate.sh checks that a Server booted this build.
 && printf '%s\n' "${IMAGE_VERSION:-local}" >/usr/lib/ghostdock/image-version

# The last step that changes files: marks /etc and /var as up to date with
# /usr, as systemd-update-done does at the end of a boot. Without the marks
# the first boot of every VM runs the ConditionNeedsUpdate= units
# (ldconfig, journal catalog, sysusers), which are for images whose /usr is
# replaced underneath them. Here dpkg keeps those up to date while it
# installs (its triggers run ldconfig and the catalog update, a package's
# postinst its sysusers), so nothing is left for a boot to do. An image built
# FROM this one that changes /usr gets them at its first boot, unless it ends
# with the same step (the desktop does).
RUN /usr/lib/systemd/systemd-update-done

# licenses: our files are Apache-2.0 (LICENSE, NOTICE); every package keeps its own license
# (/usr/share/doc/<package>/copyright), which SPDX has no one identifier for.
# ghostdock.os: the image is an OS image, unpacked onto a VM's disk
# and booted, never run as a container. No ghostdock.edition: this is the
# default edition of a Server, which the VM card calls only "Server"
# ("Server · Headless" in Create VM; based on Ubuntu 26.04).
LABEL ghostdock.login.user="ghost" \
      ghostdock.os="true" \
      org.opencontainers.image.title="Ghostdock Server, Headless (based on Ubuntu 26.04)" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.description="Ghostdock Server OS, based on Ubuntu 26.04: systemd, sshd, Docker. Not affiliated with Canonical." \
      org.opencontainers.image.licenses="Apache-2.0 AND LicenseRef-Bundled-Packages" \
      org.opencontainers.image.source="https://github.com/ghostdockhq/guest/tree/main/images/headless" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:26.04"
