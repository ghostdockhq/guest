#!/bin/sh
# The desktop of a Ghostdock Server: an XFCE desktop in the browser, streamed by Selkies
# (https://github.com/selkies-project/selkies). The one place the desktop is defined: this module
# adds it to a running Server, and the desktop image (images/desktop/Dockerfile) is built by running
# this same script on the headless image.
#
#   install.sh check      installed, at this module's release (exit 0) or not (exit 1)
#   install.sh install    installs it on a running Server and starts it
#   install.sh image      installs it while an image is built (no systemd running)
#   install.sh running    every desktop unit active (exit 0) or not
#   install.sh start      starts the desktop units
#
# What it installs:
# - Ubuntu's packages (XFCE, Xvfb, PipeWire, polkit, fonts, Firefox from Mozilla's repository).
# - Selkies in its own virtual environment, /opt/selkies, every package pinned by hash
#   (requirements.txt; requirements.in and lock.sh), with our browser tab (web/).
# - NovaDock (the dock) and the menu bar's appmenu plugin, built from pinned source with our patches,
#   and the window frames and wallpapers drawn by theme/*.py. Their build tools are removed again.
# - rootfs/: the desktop's units, scripts, XFCE's defaults and the look.
#
# It needs our headless OS: the login user ghost (uid 1000), /usr/lib/ghostdock and ghostdock.slice.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
release=$(sed -n 's/^release: *//p' "$here/module.yaml")
marker=/usr/lib/ghostdock/desktop-module

NOVADOCK_COMMIT=c94ef356f9f5ad1645d20de38f030f699424f59f
NOVADOCK_SHA256=a33a8acdc2105226b45d031115ae8c245b831fbe07ee480fc9b3391d714b6e9e
APPMENU_VERSION=25.04
APPMENU_SHA256=48d0be87b260056a65a9056a9be7e190b67a508540ebcb1fc18a67349cca0177

PACKAGES='
  xvfb xauth x11-xserver-utils x11-utils xcvt xdotool xclip xsel xfonts-base libgl1-mesa-dri
  dbus-x11 at-spi2-core
  xfce4 xfce4-terminal xfce4-notifyd xfce4-taskmanager xfce4-screenshooter
  mousepad ristretto thunar-archive-plugin xarchiver tumbler xdg-user-dirs xdg-utils
  xfce4-appmenu-plugin appmenu-gtk3-module xfce4-pulseaudio-plugin
  libwnck-3-0 libkeybinder-3.0-0 libgtk-layer-shell0
  papirus-icon-theme adwaita-icon-theme
  fonts-inter-variable fonts-jetbrains-mono
  fonts-noto-core fonts-noto-color-emoji fonts-noto-cjk fonts-dejavu-core
  pipewire pipewire-pulse wireplumber pulseaudio-utils pavucontrol
  polkitd xdg-desktop-portal xdg-desktop-portal-gtk gnome-keyring
  libva-x11-2 xprintidle
  python3 python3-venv
  nftables
  firefox
'
# Only to build NovaDock and the appmenu plugin and to draw the look: removed afterwards, each one
# that was not installed before.
BUILD_PACKAGES='
  valac meson ninja-build gcc pkg-config patch curl
  libgtk-3-dev libwnck-3-dev libkeybinder-3.0-dev libgtk-layer-shell-dev
  libxfce4panel-2.0-dev libxfce4ui-2-dev libxfconf-0-dev gobject-introspection libgirepository1.0-dev gettext
  python3-pil
'
# rootfs' programs.
EXECUTABLES='
  /usr/lib/ghostdock/desktop-activity
  /usr/lib/ghostdock/desktop-audio
  /usr/lib/ghostdock/desktop-bin/xfconf-query
  /usr/lib/ghostdock/desktop-guard
  /usr/lib/ghostdock/desktop-keyring
  /usr/lib/ghostdock/desktop-menu
  /usr/lib/ghostdock/desktop-prepare
  /usr/lib/ghostdock/desktop-session-end
  /usr/lib/ghostdock/wait-for-x
'
# The units the desktop runs; gdo-desktop-audio is one of every user manager.
UNITS='gdo-desktop-prepare.service gdo-xvfb.service gdo-desktop.service gdo-desktop-guard.service gdo-selkies.service gdo-desktop-activity.service'

before=/var/lib/ghostdock-desktop-module.packages

# Installed packages by name (a multi-arch one's architecture dropped), in C order for comm.
installed_packages() {
	dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' | sed -n 's/^ii  *\([^ :]*\).*/\1/p' | LC_ALL=C sort -u
}

installed() {
	[ -f "$marker" ] && [ "$(cat "$marker")" = "$release" ]
}

running() {
	# shellcheck disable=SC2086
	systemctl is-active --quiet $UNITS
}

needs_headless() {
	if ! id -u ghost >/dev/null 2>&1 || [ "$(id -u ghost)" != 1000 ] || [ ! -d /usr/lib/ghostdock ]; then
		echo "The desktop needs Ghostdock's headless OS (its login user ghost, uid 1000); this Server has another." >&2
		exit 1
	fi
}

apt_install() {
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

# Unpacks a GitHub or GitLab tarball without its top folder. Python, not tar: GNU tar fails on some
# of NovaDock's directories under x86 emulation (an amd64 build on an arm64 machine).
unpack() {
	python3 -c 'import sys, tarfile; t = tarfile.open(sys.argv[1]); m = [x for x in t.getmembers() if x.name.partition("/")[2]]; [setattr(x, "name", x.name.partition("/")[2]) for x in m]; t.extractall(sys.argv[2], members=m, filter="data")' "$1" "$2"
}

fetch() { # url sha256 file
	curl -fsSL --retry 5 -o "$3" "$1"
	echo "$2  $3" | sha256sum -c - >/dev/null || { echo "$1 is not the pinned download" >&2; exit 1; }
}

# NovaDock (no Ubuntu package; novadock.patch fits it to a desktop in the browser), the appmenu
# plugin as Ubuntu builds it (its translator library linked in statically) with appmenu.patch, whose
# desktop menus crashed on every file, and the drawn parts of the look. Into $1, as a root.
build_from_source() {
	out=$1 src=$2
	fetch "https://github.com/novik133/NovaDock/archive/$NOVADOCK_COMMIT.tar.gz" "$NOVADOCK_SHA256" "$src/novadock.tar.gz"
	unpack "$src/novadock.tar.gz" "$src/novadock"
	(cd "$src/novadock" && patch -p1 <"$here/novadock.patch" &&
		meson setup build --prefix=/usr --buildtype=release &&
		ninja -C build && DESTDIR="$out" ninja -C build install &&
		install -Dm644 LICENSE "$out/usr/share/doc/novadock/LICENSE")
	rm -rf "$out/usr/share/man"

	fetch "https://gitlab.com/vala-panel-project/vala-panel-appmenu/-/archive/$APPMENU_VERSION/vala-panel-appmenu-$APPMENU_VERSION.tar.gz" "$APPMENU_SHA256" "$src/appmenu.tar.gz"
	unpack "$src/appmenu.tar.gz" "$src/appmenu"
	(cd "$src/appmenu" && patch -p1 <"$here/appmenu.patch" &&
		meson setup build --prefix=/usr --buildtype=release --default-library=static \
			-Dwm_backend=wnck -Dxfce=enabled -Dvalapanel=disabled -Dmate=disabled -Dbudgie=disabled \
			-Dregistrar=disabled -Dappmenu-gtk-module=disabled -Djayatana=disabled &&
		ninja -C build applets/libappmenu-xfce.so &&
		install -Dm644 build/applets/libappmenu-xfce.so \
			"$out/usr/lib/$(gcc -dumpmachine)/xfce4/panel/plugins/libappmenu-xfce.so")

	python3 "$here/theme/xfwm4.py" "$out/usr/share/themes"
	mkdir -p "$out/usr/share/backgrounds/ghostdock"
	python3 "$here/theme/wallpaper.py" "$out/usr/share/backgrounds/ghostdock"
}

# Selkies and its browser tab: our title and the platform's icons over Selkies' own, linked as the
# app links them (app/app.vue): the SVG that follows the tab bar's light or dark, then PNG and ICO.
# web/ holds copies of brand/ (favicon.svg is icon.svg, icon-32.png is favicon-32.png); a test keeps
# them equal. ghostdock.css gives Selkies' sidebar our colors; its title and logo are settings
# (gdo-selkies.service).
install_selkies() {
	rm -rf /opt/selkies
	python3 -m venv /opt/selkies
	/opt/selkies/bin/pip install --no-cache-dir --no-deps --require-hashes -r "$here/requirements.txt"
	missing=$(find /opt/selkies -name '*.so*' -type f -exec ldd {} + 2>/dev/null | grep 'not found' | sort -u || true)
	if [ -n "$missing" ]; then
		echo "Selkies' libraries need what this OS lacks:" >&2
		echo "$missing" >&2
		exit 1
	fi
	/opt/selkies/bin/python -c 'import pixelflux, pcmflux'
	web=$(echo /opt/selkies/lib/python3*/site-packages/selkies/selkies_web)
	rm -f "$web/icon.png"
	cp "$here"/web/* "$web"/
	sed -i \
		-e 's|<title>Selkies</title>|<title>Desktop · Ghostdock</title>|' \
		-e 's|<link rel="apple-touch-icon" href="icon-512.png">|<link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png">|' \
		-e 's|</head>|<link rel="stylesheet" href="ghostdock.css"></head>|' \
		-e 's|<link rel="icon" type="image/png" href="icon.png">|<link rel="icon" type="image/svg+xml" href="icon.svg"><link rel="icon" type="image/png" sizes="32x32" href="favicon-32.png"><link rel="icon" href="favicon.ico" sizes="any">|' \
		"$web/index.html"
	grep -q '<title>Desktop · Ghostdock</title>' "$web/index.html"
	grep -q 'href="apple-touch-icon.png"' "$web/index.html"
	grep -q 'href="icon.svg"' "$web/index.html"
	grep -q 'href="ghostdock.css"></head>' "$web/index.html"
	! grep -q 'href="icon.png"' "$web/index.html"
}

# Units of desktops made before the module, which the current ones replace.
remove_old_units() {
	for unit in gdo-pulseaudio.service gdo-shm.service; do
		[ -e "/etc/systemd/system/$unit" ] || continue
		if [ "$mode" = install ]; then systemctl disable --now "$unit" 2>/dev/null || true; fi
		rm -f "/etc/systemd/system/$unit"
	done
}

install_desktop() {
	needs_headless
	export DEBIAN_FRONTEND=noninteractive
	work=$(mktemp -d)
	trap 'rm -rf "$work"' EXIT

	# Mozilla's repository for Firefox (Ubuntu's is a snap), first, so apt finds it.
	cp -r "$here/rootfs/etc/apt/." /etc/apt/

	# The image build pins Ubuntu's archive to the build's day (apt-snapshot, the headless image's);
	# on a running Server the live archive, as any apt install there.
	/usr/lib/ghostdock/apt-snapshot begin "${UBUNTU_SNAPSHOT:-}"
	apt-get update
	# The packages this Server had before the first attempt: kept even when a failed attempt left
	# the build tools behind, so a second one still removes them.
	if [ ! -f "$before" ]; then
		installed_packages >"$before.new"
		mv "$before.new" "$before"
	fi
	# shellcheck disable=SC2086
	apt_install $PACKAGES
	# shellcheck disable=SC2086
	apt_install $BUILD_PACKAGES

	build_from_source "$work/out" "$work"
	install_selkies

	# What the build added: every package that neither this Server had before nor the desktop
	# needs (its packages and everything they depend on). Never one the Server had.
	# shellcheck disable=SC2086
	{
		cat "$before"
		apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks \
			--no-replaces --no-enhances $PACKAGES | sed -n 's/^\([a-z0-9][^ <>]*\)$/\1/p; s/^ *|\{0,1\}[A-Za-z]*Depends: \([a-z0-9][^ <>]*\)$/\1/p; s/^    \([a-z0-9][^ <>]*\)$/\1/p'
	} | LC_ALL=C sort -u >"$work/kept"
	added=$(installed_packages | LC_ALL=C comm -13 "$work/kept" -)
	# A purge also removes what depends on the packages it removes: only when it removes nothing
	# kept. Otherwise the build tools stay, which costs disk and breaks nothing.
	# shellcheck disable=SC2086
	if [ -n "$added" ]; then
		removed=$(apt-get -s purge $added | sed -n 's/^Purg \([^ :]*\).*/\1/p' | LC_ALL=C sort -u)
		if [ -z "$(printf '%s\n' "$removed" | LC_ALL=C comm -12 "$work/kept" -)" ]; then
			apt-get purge -y $added
		else
			echo "Leaving the build tools installed: removing them would remove what the desktop or this Server needs." >&2
		fi
	fi
	rm -f "$before"
	/usr/lib/ghostdock/apt-snapshot end
	apt-get clean
	# An image ships without apt's lists (gdo-apt-lists fetches them at first boot); a running
	# Server keeps them, read again from the live archive after the snapshot.
	if [ "$mode" = image ]; then rm -rf /var/lib/apt/lists/*; elif [ -n "${UBUNTU_SNAPSHOT:-}" ]; then apt-get update -qq; fi

	cp -r "$work/out/." /
	cp -r "$here/rootfs/." /
	# The per-user files for /etc/skel/.config: a module carries no file or folder whose name starts
	# with a dot (readModuleFolder), so they live in skel-config.
	install -d /etc/skel/.config
	cp -r "$here/skel-config/." /etc/skel/.config/
	# A published module keeps no file modes (only *.sh are executable in it): the desktop's programs
	# are made executable here, the same in the image and on a Server.
	# tests/nuxt/images/desktop-module.test.ts keeps this list equal to rootfs' executables.
	# shellcheck disable=SC2086
	chmod 0755 $EXECUTABLES
	remove_old_units

	# The icon cache and fontconfig's system cache, up to date for every font directory: apt leaves
	# the X11 misc fonts' entry stale, and each user's first session would then build its own.
	gtk-update-icon-cache -qf /usr/share/icons/hicolor
	fc-cache -s
	# The patched appmenu plugin stays when apt updates the package: the package's own library goes
	# to .distrib instead.
	plugin=$(dpkg -L xfce4-appmenu-plugin | grep '/libappmenu-xfce\.so$')
	dpkg-divert --no-rename --divert "$plugin.distrib" --add "$plugin" >/dev/null
	# The session runs as ghost; sound and the display need these groups. ghost's home is older than
	# /etc/skel's desktop files: they go in, without replacing a file ghost already has.
	usermod --append --groups audio,video ghost
	cp -r --update=none /etc/skel/.config /home/ghost/
	chown -R ghost:ghost /home/ghost/.config
	# ghost lingers: logind starts ghost's user manager at boot and keeps it, with /run/user/1000,
	# PipeWire and the session D-Bus, across the desktop's Log Out, so Selkies' sound and the bus never
	# go away under it.
	install -d /var/lib/systemd/linger
	touch /var/lib/systemd/linger/ghost
	systemctl --global enable gdo-desktop-audio.service
	# rootfs added 50-ghostdock.rules; the folder stays as polkitd's package made it.
	chown root:polkitd /etc/polkit-1/rules.d
	chmod 0750 /etc/polkit-1/rules.d
	# nftables is here for gdo-desktop-guard's nft only, which adds and replaces its own table. The
	# package's unit loads /etc/nftables.conf, which starts with "flush ruleset": at boot it would
	# wipe gdo-guest's rules (the browser guard, the private network) and dockerd's.
	systemctl mask nftables.service
	# shellcheck disable=SC2086
	systemctl enable $UNITS

	printf '%s\n' "$release" >"$marker"
}

start_desktop() {
	systemctl daemon-reload
	loginctl enable-linger ghost
	systemctl --user --machine=ghost@ daemon-reload 2>/dev/null || true
	systemctl --user --machine=ghost@ start gdo-desktop-audio.service 2>/dev/null || true
	# A newer Selkies or guard takes over now; the session itself only once it is not running (the
	# person's own desktop is left as it is until the next start).
	systemctl try-restart gdo-selkies.service gdo-desktop-guard.service gdo-desktop-activity.service
	# shellcheck disable=SC2086
	systemctl start $UNITS
}

mode=${1:-}
case "$mode" in
check) installed ;;
running) running ;;
image)
	install_desktop
	;;
install)
	install_desktop
	start_desktop
	;;
start) start_desktop ;;
*)
	echo "usage: install.sh check | install | image | running | start" >&2
	exit 2
	;;
esac
