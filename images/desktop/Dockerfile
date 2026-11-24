# syntax=docker/dockerfile:1
# desktop: the operating system of a desktop Server ("Server · Desktop", based on
# Ubuntu 26.04): the headless OS image plus an XFCE desktop in the
# browser, streamed by Selkies (https://github.com/selkies-project/selkies).
# Like the headless image it is not run as a container: the host unpacks it
# onto a VM's disk (an OS base) and the base image's os-init boots it. The
# OS's own systemd runs the desktop as units (rootfs/etc/systemd/system/gdo-*.service):
# the display and the stream as system services, the desktop itself as a
# logind session of ghost, logged in as a display manager does (images/README.md,
# Desktop). The desktop listens on DESKTOP_PORT; the
# ghostdock.url.desktop labels tell the app, which puts it behind a private
# VM URL titled Desktop (Selkies has no login of its own here).
#
# Published as ghostdockhq/desktop. Build context: images. HEADLESS
# is the headless image of the same build, by digest (the release build
# passes it); the default, the headless candidate, is for local builds.
# Inputs that change only by pull request: requirements.txt (Selkies and
# every Python dependency, with hashes; requirements.in and lock.sh) and the
# CA bundle image, NovaDock (the dock: a commit of
# https://github.com/novik133/NovaDock, by checksum) and the appmenu plugin's
# source (vala-panel-appmenu, the release Ubuntu packages, by checksum).
# Release process: images/README.md (Releases). The look is described in images/README.md
# (Desktop: Look).
ARG HEADLESS=ghostdockhq/headless:ubuntu-26.04-rc

FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8 AS certs

# NovaDock, built from source (no Ubuntu package; novadock.patch fits it to
# a VM's desktop in the browser), the menu bar's appmenu plugin (see
# below), and the drawn parts of the look: window frames and wallpapers
# (desktop/theme/*.py).
FROM ${HEADLESS} AS build
ARG UBUNTU_SNAPSHOT=""
ARG NOVADOCK_COMMIT=c94ef356f9f5ad1645d20de38f030f699424f59f
ARG APPMENU_VERSION=25.04
RUN --mount=type=bind,from=certs,source=/etc/ssl/certs/ca-certificates.crt,target=/run/ghostdock-build/ca-certificates.crt \
    export DEBIAN_FRONTEND=noninteractive \
 && /usr/lib/ghostdock/apt-snapshot begin "${UBUNTU_SNAPSHOT}" \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      valac meson ninja-build gcc pkg-config patch \
      libgtk-3-dev libwnck-3-dev libkeybinder-3.0-dev libgtk-layer-shell-dev \
      libxfce4panel-2.0-dev libxfce4ui-2-dev libxfconf-0-dev gobject-introspection libgirepository1.0-dev gettext \
      python3-pil \
 && /usr/lib/ghostdock/apt-snapshot end
ADD --checksum=sha256:a33a8acdc2105226b45d031115ae8c245b831fbe07ee480fc9b3391d714b6e9e \
    https://github.com/novik133/NovaDock/archive/${NOVADOCK_COMMIT}.tar.gz /src/novadock.tar.gz
COPY desktop/novadock.patch /src/
# Unpacked with Python, not tar: GNU tar fails on some of this tarball's
# directories under x86 emulation (an amd64 build on an arm64 machine).
RUN python3 -c 'import sys, tarfile; t = tarfile.open(sys.argv[1]); m = [x for x in t.getmembers() if x.name.partition("/")[2]]; [setattr(x, "name", x.name.partition("/")[2]) for x in m]; t.extractall(sys.argv[2], members=m, filter="data")' \
      /src/novadock.tar.gz /src/novadock \
 && cd /src/novadock && patch -p1 < /src/novadock.patch \
 && meson setup build --prefix=/usr --buildtype=release \
 && ninja -C build && DESTDIR=/out ninja -C build install \
 && install -Dm644 LICENSE /out/usr/share/doc/novadock/LICENSE \
 && rm -rf /out/usr/share/man
# xfce4-appmenu-plugin as Ubuntu builds it (the same release, the
# translator library linked in statically), with appmenu.patch: its desktop
# menus crashed on every file. Only the plugin replaces the package's file.
ADD --checksum=sha256:48d0be87b260056a65a9056a9be7e190b67a508540ebcb1fc18a67349cca0177 \
    https://gitlab.com/vala-panel-project/vala-panel-appmenu/-/archive/${APPMENU_VERSION}/vala-panel-appmenu-${APPMENU_VERSION}.tar.gz /src/appmenu.tar.gz
COPY desktop/appmenu.patch /src/
RUN python3 -c 'import sys, tarfile; t = tarfile.open(sys.argv[1]); m = [x for x in t.getmembers() if x.name.partition("/")[2]]; [setattr(x, "name", x.name.partition("/")[2]) for x in m]; t.extractall(sys.argv[2], members=m, filter="data")' \
      /src/appmenu.tar.gz /src/appmenu \
 && cd /src/appmenu && patch -p1 < /src/appmenu.patch \
 && meson setup build --prefix=/usr --buildtype=release --default-library=static \
      -Dwm_backend=wnck -Dxfce=enabled -Dvalapanel=disabled -Dmate=disabled -Dbudgie=disabled \
      -Dregistrar=disabled -Dappmenu-gtk-module=disabled -Djayatana=disabled \
 && ninja -C build applets/libappmenu-xfce.so \
 && install -Dm644 build/applets/libappmenu-xfce.so \
      /out/usr/lib/$(gcc -dumpmachine)/xfce4/panel/plugins/libappmenu-xfce.so
COPY desktop/theme/ /src/theme/
RUN python3 /src/theme/xfwm4.py /out/usr/share/themes \
 && mkdir -p /out/usr/share/backgrounds/ghostdock \
 && python3 /src/theme/wallpaper.py /out/usr/share/backgrounds/ghostdock

FROM ${HEADLESS}
# Again after FROM, for the base.name label below: exactly what this build
# is on (in CI the headless image by digest).
ARG HEADLESS

# The archive snapshot, as for the headless image. Firefox comes from
# Mozilla's repository, which has no snapshots: it is the current release
# on the day of the build.
ARG UBUNTU_SNAPSHOT=""
# This image's own OCI labels, as for the headless image.
ARG IMAGE_VERSION=""
ARG IMAGE_CREATED=""
ARG IMAGE_REVISION=""

COPY desktop/rootfs/etc/apt/ /etc/apt/

RUN --mount=type=bind,from=certs,source=/etc/ssl/certs/ca-certificates.crt,target=/run/ghostdock-build/ca-certificates.crt \
    export DEBIAN_FRONTEND=noninteractive \
 && /usr/lib/ghostdock/apt-snapshot begin "${UBUNTU_SNAPSHOT}" \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      xvfb xauth x11-xserver-utils x11-utils xcvt xdotool xclip xsel xfonts-base libgl1-mesa-dri \
      dbus-x11 at-spi2-core \
      xfce4 xfce4-terminal xfce4-notifyd xfce4-taskmanager xfce4-screenshooter \
      mousepad ristretto thunar-archive-plugin xarchiver tumbler xdg-user-dirs xdg-utils \
      xfce4-appmenu-plugin appmenu-gtk3-module xfce4-pulseaudio-plugin \
      libwnck-3-0 libkeybinder-3.0-0 libgtk-layer-shell0 \
      papirus-icon-theme adwaita-icon-theme \
      fonts-inter-variable fonts-jetbrains-mono \
      fonts-noto-core fonts-noto-color-emoji fonts-noto-cjk fonts-dejavu-core \
      pipewire pipewire-pulse wireplumber pulseaudio-utils pavucontrol \
      polkitd xdg-desktop-portal xdg-desktop-portal-gtk gnome-keyring \
      libva-x11-2 xprintidle \
      python3 python3-venv \
      nftables \
      firefox \
 && /usr/lib/ghostdock/apt-snapshot end \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Selkies in its own virtual environment, every package pinned by hash.
COPY desktop/requirements.txt /tmp/selkies-requirements.txt
RUN python3 -m venv /opt/selkies \
 && /opt/selkies/bin/pip install --no-cache-dir --no-deps --require-hashes -r /tmp/selkies-requirements.txt \
 && rm /tmp/selkies-requirements.txt \
 && missing=$(find /opt/selkies -name '*.so*' -type f -exec ldd {} + 2>/dev/null | grep 'not found' | sort -u) \
 && { [ -z "$missing" ] || { echo "Selkies' libraries need what the image lacks:" >&2; echo "$missing" >&2; exit 1; }; } \
 && /opt/selkies/bin/python -c 'import pixelflux, pcmflux'
# The browser tab: our title and the platform's icons over Selkies' own,
# linked as the app links them (app/app.vue): the SVG that follows the tab
# bar's light or dark, then PNG and ICO. Copies of brand/ (favicon.svg is
# icon.svg, icon-32.png is favicon-32.png); a check in images/ keeps them
# equal. ghostdock.css gives Selkies' sidebar our colors; its title and
# logo are settings (gdo-selkies.service).
COPY desktop/web/ /tmp/selkies-web/
RUN web=$(echo /opt/selkies/lib/python3*/site-packages/selkies/selkies_web) \
 && rm -f "$web/icon.png" \
 && cp /tmp/selkies-web/* "$web"/ && rm -rf /tmp/selkies-web \
 && sed -i \
      -e 's|<title>Selkies</title>|<title>Desktop · Ghostdock</title>|' \
      -e 's|<link rel="apple-touch-icon" href="icon-512.png">|<link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png">|' \
      -e 's|</head>|<link rel="stylesheet" href="ghostdock.css"></head>|' \
      -e 's|<link rel="icon" type="image/png" href="icon.png">|<link rel="icon" type="image/svg+xml" href="icon.svg"><link rel="icon" type="image/png" sizes="32x32" href="favicon-32.png"><link rel="icon" href="favicon.ico" sizes="any">|' \
      "$web/index.html" \
 && grep -q '<title>Desktop · Ghostdock</title>' "$web/index.html" \
 && grep -q 'href="apple-touch-icon.png"' "$web/index.html" \
 && grep -q 'href="icon.svg"' "$web/index.html" \
 && grep -q 'href="ghostdock.css"></head>' "$web/index.html" \
 && ! grep -q 'href="icon.png"' "$web/index.html"

COPY --from=build /out/ /
COPY desktop/rootfs/ /
# XFCE's defaults (the look, the menu bar, the window manager, the session)
# are system channels in rootfs/etc/xdg/xfce4/xfconf; per-user files (the
# dock's config, the menu bar's and terminal's CSS) come from
# rootfs/etc/skel. NovaDock starts from /etc/xdg/autostart.
# -f: COPY keeps the files' timestamps, older than the cache apt left.
RUN gtk-update-icon-cache -qf /usr/share/icons/hicolor \
 # fontconfig's system cache, up to date for every font directory: apt
 # leaves the X11 misc fonts' entry stale (their directory changes after
 # fontconfig's trigger ran), and each user's first session would then
 # build its own cache.
 && fc-cache -s \
 # The patched appmenu plugin (build stage) stays when apt updates the
 # package: the package's own library goes to .distrib instead.
 && plugin=$(dpkg -L xfce4-appmenu-plugin | grep '/libappmenu-xfce\.so$') \
 && dpkg-divert --no-rename --divert "${plugin}.distrib" --add "${plugin}" \
 # The session runs as the headless image's login user, ghost; sound and the
 # display need these groups. Its home was made before rootfs/etc/skel
 # existed, so the per-user files go in here.
 && usermod --append --groups audio,video ghost \
 && cp -r /etc/skel/.config /home/ghost/ \
 && chown -R ghost:ghost /home/ghost/.config \
 # ghost lingers: logind starts ghost's user manager at boot and keeps it, with
 # /run/user/1000, PipeWire and the session D-Bus, across the desktop's
 # Log Out, so Selkies' sound and the bus never go away under it.
 && install -d /var/lib/systemd/linger && touch /var/lib/systemd/linger/ghost \
 # The sound devices Selkies streams, a unit of every user manager.
 && systemctl --global enable gdo-desktop-audio.service \
 # rootfs/ added 50-ghostdock.rules; the folder stays as polkitd's package
 # made it (polkitd reads it, users do not).
 && chown root:polkitd /etc/polkit-1/rules.d && chmod 0750 /etc/polkit-1/rules.d \
 # nftables is here for gdo-desktop-guard's nft only, which adds and replaces
 # its own table. The package's unit loads /etc/nftables.conf, which starts
 # with "flush ruleset": at boot it would wipe gdo-guest's rules (the browser
 # guard, the private network) and dockerd's. The base image masks it for the
 # same reason; the OS must not run it either.
 && systemctl mask nftables.service \
 # /dev/shm is the OS's own tmpfs (half the VM's memory, used only when
 # something is in it), enough for the X server and the stream: no resize.
 && systemctl enable gdo-desktop-prepare.service gdo-xvfb.service \
      gdo-desktop.service gdo-desktop-guard.service gdo-selkies.service \
      gdo-desktop-activity.service

# Away from the ports a VM's own apps tend to use (3000, 5173, 8080, …)
# and below Linux's ephemeral range (32768+), so neither takes it first.
# Selkies reads it from selkies.env, the app from the URL label: one number.
ARG DESKTOP_PORT=14080
RUN printf 'SELKIES_PORT=%s\n' "${DESKTOP_PORT}" >/etc/ghostdock/selkies.env \
 # The build this OS came from, as in the headless image (images/validate.sh).
 && printf '%s\n' "${IMAGE_VERSION:-local}" >/usr/lib/ghostdock/image-version

# The last step that changes files, as in the headless image: this image
# changed /usr, so it marks /etc and /var as up to date again, and its first
# boot skips the ConditionNeedsUpdate= units that dpkg already did the work of.
RUN /usr/lib/systemd/systemd-update-done

# HTTP URLs are private unless labelled public, so no .public label here.
# The headless image's OCI labels would carry over: this image sets its own
# (ghostdock.os=true and the login user carry over as they are: it is an OS
# image too). ghostdock.edition: the VM card says "Server · Desktop".
# licenses as for the headless image; Selkies and its
# Python dependencies keep theirs in /opt/selkies (each package's dist-info),
# NovaDock (GPL-3.0) in /usr/share/doc/novadock.
# ghostdock.setting.workKeepsAwakeMinutes: a desktop's work alone (a video
# for nobody) keeps it awake four hours after the last input; a server's
# default is unlimited (https://docs.ghostdock.ai/vms/sleep). The only difference between the two.
LABEL ghostdock.labels.format="2" \
      ghostdock.url.desktop.port="${DESKTOP_PORT}" \
      ghostdock.url.desktop.title="Desktop" \
      ghostdock.setting.workKeepsAwakeMinutes="240" \
      ghostdock.edition="Desktop" \
      org.opencontainers.image.title="Ghostdock Server, Desktop (based on Ubuntu 26.04)" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.description="Ghostdock Server OS with a browser desktop, based on Ubuntu 26.04. Not affiliated with Canonical." \
      org.opencontainers.image.licenses="Apache-2.0 AND LicenseRef-Bundled-Packages" \
      org.opencontainers.image.source="https://github.com/ghostdockhq/guest/tree/main/images/desktop" \
      org.opencontainers.image.base.name="${HEADLESS}"
