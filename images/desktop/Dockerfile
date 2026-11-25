# syntax=docker/dockerfile:1
# desktop: the operating system of a desktop Server ("Server · Desktop", based on
# Ubuntu 26.04): the headless OS image plus Ghostdock's desktop, an XFCE desktop
# in the browser streamed by Selkies (https://github.com/selkies-project/selkies).
# Like the headless image it is not run as a container: the host unpacks it
# onto a VM's disk (an OS base) and the base image's os-init boots it.
#
# The desktop itself is the requirement module ghostdock/desktop
# (requirement-modules/ghostdock/desktop): its install.sh, which also adds the
# desktop to a running Server, is what this build runs. The module holds every
# file of the desktop (units, scripts, the look, Selkies' pinned requirements,
# the dock's and the appmenu plugin's patches); this file holds only what an
# image has and a module does not: its labels, its version file and the
# archive snapshot. How the desktop works: images/README.md (Desktop); its look:
# requirement-modules/ghostdock/desktop/README.md.
#
# Published as ghostdockhq/desktop. Build context: images, with the module as the
# named context desktop-module (images/platform-images.json, "contexts"; for a
# local build: images/README.md). HEADLESS is the headless image of the same
# build, by digest (the release build passes it); the default, the headless
# candidate, is for local builds. Release process: images/README.md (Releases).
ARG HEADLESS=ghostdockhq/headless:ubuntu-26.04-rc

FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8 AS certs

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

# The module, run as on a Server, with the archive pinned to the build's day.
RUN --mount=type=bind,from=desktop-module,target=/run/ghostdock-build/desktop-module \
    --mount=type=bind,from=certs,source=/etc/ssl/certs/ca-certificates.crt,target=/run/ghostdock-build/ca-certificates.crt \
    UBUNTU_SNAPSHOT="${UBUNTU_SNAPSHOT}" sh /run/ghostdock-build/desktop-module/install.sh image

# The port Selkies serves on is the module's (rootfs/etc/ghostdock/selkies.env);
# the app reads it from the URL label, so the build checks that they agree.
ARG DESKTOP_PORT=14080
RUN grep -qx "SELKIES_PORT=${DESKTOP_PORT}" /etc/ghostdock/selkies.env \
 # The build this OS came from, as in the headless image (images/validate.sh).
 && printf '%s\n' "${IMAGE_VERSION:-local}" >/usr/lib/ghostdock/image-version

# The last step that changes files, as in the headless image: this image
# changed /usr, so it marks /etc and /var as up to date again, and its first
# boot skips the ConditionNeedsUpdate= units that dpkg already did the work of.
RUN /usr/lib/systemd/systemd-update-done

# HTTP URLs are private unless labelled public, so no .public label here.
# The headless image's OCI labels would carry over: this image sets its own
# (ghostdock.os=true and the login user carry over as they are: it is an OS
# image too). ghostdock.edition: the VM card says "Server · Desktop" (a Server
# that has the module says so too, from its guest's report).
# licenses as for the headless image; Selkies and its
# Python dependencies keep theirs in /opt/selkies (each package's dist-info),
# NovaDock (GPL-3.0) in /usr/share/doc/novadock.
# ghostdock.setting.workKeepsAwakeMinutes: a desktop's work alone (a video
# for nobody) keeps it awake four hours after the last input; a server's
# default is unlimited (https://docs.ghostdock.ai/vms/sleep).
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
