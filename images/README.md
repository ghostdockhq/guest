# Platform images

Ghostdock's platform images, based on Ubuntu 26.04, with systemd, sshd and
Docker's engine: the operating systems of [Ghostdock](https://ghostdock.ai) Servers.
They are OS images (`LABEL ghostdock.os=true`): a VM created from one boots
it as its own system, from a disk of its own, as on any cloud VM. SSH in,
`apt install`, `docker compose up`, reboot, and it is still yours. They are
never run as containers.

| Directory | Image | |
|---|---|---|
| [headless/](headless/) | `ghostdockhq/headless:ubuntu-26.04` | Server · Headless (based on Ubuntu 26.04), the OS of the system and template `headless` |
| [desktop/](desktop/) | `ghostdockhq/desktop:ubuntu-26.04` | Server · Desktop: the headless image plus an XFCE desktop in the browser, the OS of `desktop` |
| [actions-runner/](actions-runner/) | `ghostdockhq/actions-runner:ubuntu-26.04` | The headless image plus GitHub's runner: one GitHub Actions job per VM, ready at boot |

Each image has its own Docker Hub repository with the same tags: `ubuntu-26.04`
and `latest` (stable), `ubuntu-26.04-rc` (the newest candidate) and a dated
`ubuntu-26.04-<yyyymmdd>-<sha7>-<run>` per build. The tag names the base the
image is built on, as Docker Hub images do; the products are ours and never
called Ubuntu: the images are modified Ubuntu, which Canonical's trademark
policy lets us describe as "based on Ubuntu" but not name so, and each Docker
Hub page says it is not affiliated with or endorsed by Canonical.
The labels `ghostdock.os=true` (an OS image) and `ghostdock.edition` (what the
VM card says after "Server": `Desktop` on the desktop image, none on the
headless one, the default edition) say what boots. The build context is this
directory, so the images share [LICENSE](LICENSE),
`validate.sh`, the apt snapshot helper and Docker's key (`docker.asc`).

[platform-images.json](platform-images.json) is the one list of them: the release build builds,
validates and promotes every image in it, and nothing else names them one by one.

## Releases

1. **Build.** On every change to these files, every Monday (for Ubuntu's security updates) and by
   hand, [build.sh](build.sh) builds every image of the list in its order, each on the headless
   image of the same build by digest, with Ubuntu's packages from the archive snapshot of that day
   (`snapshot.ubuntu.com`). It pushes candidates only: the dated tag and `-rc`.
2. **Validate.** [validate.sh](validate.sh) boots each candidate as a real Server and checks it
   (systemd, the login user, the VM's environment, SSH, apt, Docker, a stop and a start, a halt),
   then runs the image's own checks, `<name>/validate.sh`. It works against any Ghostdock
   instance where the `ghostdock` CLI is logged in.
3. **Promote.** Only a build whose every image passed moves the stable tags (`ubuntu-26.04`,
   `latest`), all images together, as a copy of the validated digests: nothing is rebuilt.

The images live on Docker Hub, which every Ghostdock host caches, so only the first VM on a host
downloads one.

## A new platform image

Same software for everyone, on VMs that come and go: an OS image built on ours. A few lines on top of
headless (or desktop), never a fork, with nothing per VM in it (per VM is a value of the VM's
environment that the image's units read) and no platform software (that comes from the base
image). A new one is:

1. `images/<name>/Dockerfile`, `FROM ${HEADLESS}` with `ARG HEADLESS=ghostdockhq/headless:ubuntu-26.04-rc`
   (the release build passes the headless image of the same build, by digest), its packages from the
   apt snapshot as the desktop's are, `/usr/lib/ghostdock/image-version` written and
   `systemd-update-done` as its last step (validate.sh checks that the first boot had nothing to
   update), and its own `org.opencontainers.image.*` labels.
2. A line in [platform-images.json](platform-images.json): its `name`, its `base`, the `edition` its
   label names (empty for none) and the `resources` its validation VM needs.
3. Optional: `images/<name>/validate.sh` with its own checks, which [validate.sh](validate.sh) sources
   after the checks every OS image has.
4. Its Docker Hub page: a short description (the same as its `org.opencontainers.image.description`
   label) and an overview. The release build creates the repository, public, before its first push.

The next build builds it, validates it, and promotion moves its stable tags with the others. A
Ghostdock template names it as its `system`, by tag.

## Docker Hub

Each image has its own public repository under [ghostdockhq](https://hub.docker.com/u/ghostdockhq). Its short description is the same as the image's `org.opencontainers.image.description` label, and its overview links here.

## License

Our files here (the Dockerfiles, `rootfs/`, the scripts and the patches) are under the
[Apache License 2.0](LICENSE), shipped in the image with the [NOTICE](NOTICE) as
`/usr/share/doc/ghostdock/LICENSE` and `NOTICE`. The license grants no rights to the Ghostdock
name or logo. Everything else in the image
is Ubuntu's: each package keeps its license in `/usr/share/doc/<package>/copyright`,
and the sources of those packages are in the Ubuntu archive (`apt-get source`).
Docker's engine, CLI and plugins are Docker's packages (Apache-2.0,
`/usr/share/doc/docker-ce/copyright` and the others' own).
In the desktop, Selkies and its Python dependencies keep theirs in `/opt/selkies`
(each package's `dist-info`), and NovaDock (GPL-3.0) in `/usr/share/doc/novadock`;
its source is the pinned upstream commit plus `desktop/novadock.patch`. The menu
bar's appmenu plugin library is Ubuntu's release of vala-panel-appmenu (LGPL-3.0,
`/usr/share/doc/xfce4-appmenu-plugin/copyright`) plus `desktop/appmenu.patch`. The `org.opencontainers.image.licenses` label
says this as `Apache-2.0 AND LicenseRef-Bundled-Packages`.

## How it runs

The host unpacks the image's layers onto a VM's disk once per host and
digest (an OS base), and a create clones that disk. The base image boots it:
the host's kernel, then the base image's `os-init`, which adds the
platform's units (gdo-guest, the private network, memory online) under
`/run` and switches to the image's own `/sbin/init`. One systemd boots, the
OS's. gdo-guest configures the network from the kernel command line, writes
`/etc/hostname`, `/etc/hosts` and `/etc/resolv.conf` while they carry its
marker line, and serves the host on vsock; nothing Ghostdock-specific needs
to be installed in the OS.

What a VM can do follows from the image's labels, never its name:
`ghostdock.os=true` makes it a Server, `ghostdock.login.user=ghost` says
where SSH, the terminal and commands land. The OCI labels
`org.opencontainers.image.version` (the published tag, also written to
`/usr/lib/ghostdock/image-version`, as the labels are not on the disk),
`.created` (the Ubuntu archive snapshot's moment) and `.revision` (the git
commit). The desktop inherits the `ghostdock.*` labels and sets its own OCI
ones.

Masked units: consoles, the kernel's module loader, networkd, resolved,
timesyncd, systemd-firstboot and e2scrub. The network, DNS and clock are
gdo-guest's and the host's. The kernel loads no modules: every driver is built in, so
`modprobe` of one succeeds (the image has the kernel's built-in index) and loads nothing, and a
driver that is not built in cannot be added.

The same image also boots in a container (on a Ghostdock Docker host). Two
additions apply only there. A generator,
`usr/lib/systemd/system-generators/gdo-container-journald`, writes
`ReadKMsg=no` for journald when `systemd-detect-virt --container` is true:
Sysbox puts `/dev/null` at `/dev/kmsg`, and journald exits when it cannot
poll that file. The `sys-kernel-config`, `sys-kernel-debug` and
`sys-kernel-tracing` mounts carry `ConditionVirtualization=!container`,
because those filesystems belong to the host kernel and a failed mount stops
the boot. On a microVM the generator writes nothing and the mounts run as
usual. The desktop image is this one plus its desktop, so it has both.

Docker is Docker's own packages (`docker-ce`, containerd, the Compose and
buildx plugins) from Docker's apt repository, at the Dockerfile's pins, with
Docker's source and key kept: after the create, `apt upgrade` updates
Docker like every other package. `ghost` is in the `docker` group. Every
Docker client on the VM goes through gdo-guest's Docker API proxy on
`/run/docker.sock` (dockerd's own socket is internal), and laptops on the
private network through the Docker context on port 2376 (`ghostdock docker
context <vm>`).

## Compared with an Ubuntu server

The image is Ubuntu's minimized Docker image (`ubuntu:26.04`) plus systemd,
sshd, Docker and the packages a server is expected to have. What differs
from an Ubuntu cloud VM:

**Package lists.** The image ships none (they would be the build's).
`gdo-apt-lists.service` fetches them once in the background on a VM's first
boot (about 30 MB, a few seconds); then `apt-daily.timer` keeps them current
(`apt.conf.d/10periodic`), also after a stopped VM wakes. Three of the base
image's apt settings stay, to keep apt's files on each VM at about 45 MB
instead of 255 MB: no binary package cache (`docker-clean`; each apt command
takes about 0.8 s longer), compressed lists (`docker-gzip-indexes`), and no
long package descriptions (`docker-no-languages`; `apt show` prints the
one-line summary). dpkg syncs to disk, and `autoremove` behaves as on
Ubuntu. `unattended-upgrades` installs security updates.

**`halt` powers off.** `halt`, `systemctl halt` and `shutdown -H` stop the
VM like `poweroff` (`systemd-halt.service.d/gdo-poweroff.conf`). A plain halt
stops the kernel and leaves the VM's machine running with nothing in it,
which the platform showed as a running VM that never answered (2026-11-05).

**Not installed, one command away:**

| Missing | Instead |
|---|---|
| man pages and `/usr/share/doc` (`man` says the system is minimized) | `sudo unminimize` reinstalls every package with its docs (a few minutes) |
| cron | systemd timers, also per user (`systemctl --user`, `systemd-run --on-calendar=…`); or `sudo apt install cron` |
| rsyslog, full vim, `add-apt-repository` (`software-properties-common`) | `sudo apt install …` |

**Not supported:**

- **snap.** snapd needs squashfs and AppArmor, which the VM's kernel does
  not have. Use apt, a vendor's apt repository, a Docker image or the
  upstream binary (certbot: `apt install certbot`).
- **The kernel and the boot** are the platform's: no loadable kernel modules
  (`modprobe` of a built-in driver works, `modprobe dm_thin_pool` does not), no
  kernel packages of your own, no `do-release-upgrade` to another kernel.
  A network manager of your own fights gdo-guest for `eth0`.

## SSH

`openssh-server` runs in the VM and is the one way in: shells, the web
terminal and the app's commands are SSH sessions (PAM, logind), and `scp`,
`sftp` and `rsync` work. Ghostdock's gateway trusts the VM's sshd through a
user CA it gives `sshd` on its command line (not in `/etc/ssh`), so
`sshd_config` is yours: the image's `sshd_config.d/ghostdock.conf` only
turns passwords and root logins off. Keys in `~/.ssh/authorized_keys` work
over the private network. When sshd does not answer, `ghostdock vm ssh
<vm> --rescue` opens a rescue shell without it.

## The private network

Devices of your organization reach the VM's address over the private
network; the
VM sees them as `198.18.0.0/15`. gdo-guest's browser guard sits in front
of every TCP connection from them: browsers are sent to the VM's HTTPS
name, tools pass.

Firewall rules for these clients go in the input path: `iptables -A INPUT -s
198.18.0.0/15 …`, or an nft chain on `hook input` as the desktop image's
`desktop-guard` does. Rules in `FORWARD` or `DOCKER-USER` no longer see them,
even for a container's published port: the guard connects to it from inside
the VM, through `OUTPUT`. Leave `198.18.0.0` alone; it is the platform's
gdo-ingress, which brings the HTTPS route.

## Users

As on a cloud VM, you work as a normal user and become root when you need it.
SSH, the web terminal, scp and the app's commands land as `ghost`
(uid 1000, home `/home/ghost`), in that home, and `sudo` needs no password:
`sudo -i` for a root shell. Ubuntu's `ubuntu` user is gone; `ghost` has its
uid. The `ghostdock.login.user=ghost` label sets this, read when the VM is
created; an image built `FROM` these inherits it.

Services keep their own users, and systemd starts them as root, as on any
Ubuntu.

## The ghostdock CLI

`ghostdock` (and `gdock`) work on every Server. The image holds only a small launcher,
[`/usr/local/bin/ghostdock`](headless/rootfs/usr/local/bin/ghostdock), so the CLI is never as old
as the image. The first run installs the latest release for that user into
`~/.local/share/ghostdock/bin`, and at most once a day a run updates it in the background.
Restored from an old snapshot, the first run is the old version and the next ones the new one.
`GHOSTDOCK_NO_AUTO_UPDATE=1` keeps the installed version.

The CLI connects to the API of the app the VM belongs to: the platform sets `GHOSTDOCK_API_URL` (`https://api.<domain>`) on every VM.
Nothing is logged in beforehand. `ghostdock login` prints a link to approve in your browser.

Tab completion works in bash from the first run on, with nothing to set up.

## Environment variables

gdo-guest writes the VM's variables into the OS at every config push: to
`/run/ghostdock/env` (root only, `KEY="value"` lines) and to
`/run/ghostdock/shell.env` (root and `ghost`'s group, 0640), which login
shells read through `/etc/profile.d/ghostdock-env.sh`.

Services get them only when they ask for them, as on a VM. A service opts
in with one line; systemd reads the file as root before it starts the
service, so the service's own user needs no access, and no other local user
can read the values.

Your own service:

```ini
# /etc/systemd/system/myapp.service
[Unit]
After=gdo-guest.service

[Service]
ExecStart=/usr/bin/node /srv/myapp/server.js
EnvironmentFile=/run/ghostdock/env
```

A service from a package (nginx, postgres, …): add a drop-in, which survives
package updates. `systemctl edit nginx` opens it; enter

```ini
[Unit]
After=gdo-guest.service

[Service]
EnvironmentFile=/run/ghostdock/env
```

then `systemctl restart nginx`. A changed variable reaches a service at its
next start, and a shell at its next login.

The files are in memory, never on the disk or in a snapshot of it: after a boot they exist once
gdo-guest has the host's first config. `After=gdo-guest.service` waits for that
(gdo-guest is ready then); without it a service started early at
boot fails on the missing file.

## Desktop

The desktop image is the headless image of the same build plus an XFCE
desktop, streamed to the browser by [Selkies](https://github.com/selkies-project/selkies)
2 (MPL-2.0), the stack linuxserver.io's webtop uses. Like the headless image
it is an OS image: `ghostdock vm up desktop`
makes a Server that boots it as its own system (it inherits `ghostdock.os=true`
and the login user), and the app makes the Desktop URL from its
`ghostdock.urls.desktop` labels. Everything runs as units of the OS's own
systemd: the display and the stream as system services, the desktop itself
as a login session of `ghost` (see [The login session](#the-login-session)).
`/dev/shm` is the OS's own tmpfs (half the VM's memory, used only when
something is in it), which the X server and the stream share frames
through. The units, in this order:

| Unit | Does |
|---|---|
| `gdo-desktop-prepare` | the X server's directory on `/run` (`/run/ghostdock-desktop`), and a fresh X cookie each boot |
| `gdo-xvfb` | the display `:1`, a virtual X server without a GPU |
| `gdo-desktop` | ghost's login session on that display: XFCE, with the VM env as in a shell |
| `gdo-desktop-guard` | drops port 14080 for devices on the private network (`198.18.0.0/15`), except gdo-ingress (`198.18.0.0`): `/usr/lib/ghostdock/desktop-guard`, before Selkies starts |
| `gdo-selkies` | the stream on port 14080 (`DESKTOP_PORT`, the VM URL titled Desktop): web client, websocket (`/api/websockets`), health (`/api/health`) |

- **Access.** Selkies' own login is off. The labels
  `ghostdock.urls.desktop.port=14080` and
  `ghostdock.urls.desktop.title=Desktop` make the app put the port behind
  a private VM URL (HTTP URLs are private by default), which signs the
  user in; the card shows a button for every titled URL, so this one is
  **Desktop**. Selkies' same-origin check on the websocket stays on. Over the
  private network
  the desktop is reached only through gdo-ingress, at
  `https://<vm>--<org>.<net domain>:14080`, which checks the device's
  organization; `gdo-desktop-guard` drops the port for devices directly.
- **User.** The session runs as `ghost`, the same user SSH, the web terminal
  and commands land as (see [Users](#users)).
- **Sound** is PipeWire, in ghost's user manager, with its PulseAudio server
  (`pipewire-pulse`), which Selkies and `pactl` talk to. `gdo-desktop-audio`,
  a user unit, adds the `output` and `input` null sinks Selkies streams and
  makes them the defaults; Selkies adds its virtual microphone when a
  browser sends one.
- **Firefox** comes from Mozilla's apt repository (Ubuntu ships a snap, which
  does not run here), pinned above Ubuntu's package. It is the current
  release on the build's day.
- **Selkies** lives in `/opt/selkies`, a virtual environment installed from
  `desktop/requirements.txt`: every package pinned with hashes, wheels only.
  Change `desktop/requirements.in`, then run `desktop/lock.sh` (needs uv).
- **nftables** is installed for `gdo-desktop-guard`'s `nft` only, which adds
  and replaces its own table `inet gdo_desktop_guard`. `nftables.service` is
  masked: it loads `/etc/nftables.conf`, whose `flush ruleset` would wipe
  gdo-guest's rules and dockerd's at boot.
- **Not included:** GPU encoding, and Selkies' gamepad and webcam
  interposers.

### The login session

The desktop is logged in as a display manager logs a user in:
`gdo-desktop.service` opens a PAM session (`PAMName=`, the
service `/etc/pam.d/ghostdock-desktop`: no authentication, as with a display
manager's autologin; account and session only, without `login`'s motd) as
`ghost`, with `XDG_SESSION_TYPE=x11`. pam_systemd registers it with logind
and moves it into its own scope, `session-<id>.scope` under
`user-1000.slice`. It runs Debian's X session script, `/etc/X11/Xsession
startxfce4`, as LightDM does: `~/.xsessionrc` is read, the session's
variables reach ghost's user manager and D-Bus, and `startxfce4` starts
XFCE. What that gives:

- **One user manager and one session D-Bus** for the desktop and every SSH
  login (`/run/user/1000/bus`). From SSH, `notify-send`, `xfconf-query`,
  `xfce4-session-logout` or `xdg-open` reach the desktop as they are;
  `systemctl --user` works in the desktop's terminal.
- **Restart and Shut Down** in the Log Out dialog: logind asks polkit, and
  `/etc/polkit-1/rules.d/50-ghostdock.rules` lets `ghost` do anything
  without a password, as `/etc/sudoers.d/ghost` already does. Admin dialogs
  and `pkexec` work the same way.
- **The desktop's plumbing:** PipeWire (see Sound), the portals
  (`xdg-desktop-portal` with the GTK backend: FileChooser, OpenURI,
  Settings; `xfce-portals.conf` picks them), and gnome-keyring as the Secret
  Service.

`ghost` lingers (`/var/lib/systemd/linger/ghost`): logind starts ghost's user
manager at boot and keeps it, with `/run/user/1000`, PipeWire and the bus,
while no session is open. Selkies is not in the session (it is the display
server's side) and reaches the bus and PipeWire through `desktop.env`.

**Log Out** ends the session and `Restart=` logs ghost in again within about
3 seconds. The session's programs are in its scope, not in the unit, so the
unit's `ExecStopPost=` (`/usr/lib/ghostdock/desktop-session-end`, as root)
stops the old scope first: with a display manager they would die with the X
server, restarted at every login, but Xvfb stays, and logind keeps a closed
session's processes (`KillUserProcesses=no`, which SSH logins need for tmux
and `nohup`). Without it the dock would survive into the next session, and
the next dock would not start. It stops the scope rather than the session:
logind ignores `loginctl terminate-session` for a session already closing.

Found while building it (2026-11-06):

- **Shut Down stops the VM, and an open desktop tab starts it again**: Selkies
  reconnects, and the Desktop URL wakes the VM (`autoWake`), so within
  seconds it runs again (stop reason `exited`, then a boot with trigger
  `wake`). Close the tab first to keep it stopped. An ephemeral VM is
  deleted by a Shut Down, as by any `poweroff`.
- **Idle stop follows use, not the tab**:
  `gdo-desktop-activity` (as ghost) writes `/run/ghostdock-desktop/activity`
  every 10 s, the desktop's port and the last input (`xprintidle`, the X
  server's idle time: Selkies delivers the browser's input as X input) or
  sound (the `output` sink `RUNNING`). gdo-guest reports it, and gdo-ingress
  stops counting the Desktop URL's traffic while the file is fresh. Measured
  on a real VM: an untouched open tab moved the idle clock every minute;
  the X idle time grows without end under it, and one click sets it back to
  under a second. Selkies itself injects no input. A file not written for a
  minute (the service gone) makes the URL count again.
- **The keyring needs no password.** The desktop logs in without one, so
  pam_gnome_keyring has nothing to unlock a login keyring with, and the
  first program storing a secret would ask for a password for a new
  keyring. So `desktop-keyring` (an `ExecStartPre=` of `gdo-desktop`, as
  ghost) writes a login keyring without a password once, in gnome-keyring's
  plain-text format: unlocking it never prompts, and libsecret programs
  (browsers, VS Code, Git's credential helper) unlock it silently. It never
  touches an existing keyring, so a password set later stays. Its secrets
  are unencrypted in `~/.local/share/keyrings`, as with an empty password
  at the prompt: whoever reads ghost's files reads them, and every program
  of ghost's session can read an unlocked keyring anyway.
  `gnome-keyring-daemon --unlock` with an empty password did not create one
  (it hung).
- **No ScreenCast portal on X11**: it needs a Wayland compositor's backend.
  Browsers capture the X display directly instead.
- **libva-x11-2 is installed by name**: Selkies' pixelflux bundles FFmpeg,
  which links `libva-x11.so.2` from the image. PulseAudio used to pull it in
  (through `libasound2-plugins` and `libavcodec`); when PipeWire replaced it,
  the library went with it, and every new desktop showed "Waiting for
  stream…" while sound still played (2026-11-06). The build now fails when
  any library under `/opt/selkies` has an unresolved dependency, and
  `validate.sh` checks that pixelflux loads and Selkies logged no capture
  failure. A Server made from the broken image (20261106-28fd7ab) is fixed
  with `sudo apt-get install -y libva-x11-2 && sudo systemctl restart
  gdo-selkies`.
- **RTKit is not installed**: PipeWire logs warnings about it at every boot
  and runs without realtime priority, which a VM without a sound card does
  not need.
- **WirePlumber sets the defaults late**: until it is up, pipewire-pulse
  answers `set-default-sink` with "Not supported", so `desktop-audio` tries
  again for up to 10 seconds.
- **The VM env reaches ghost's user services too**: Xsession hands every
  variable of the session to the user manager and D-Bus
  (`95dbus_update-activation-env`), as it was when the session started. A
  changed variable reaches them at the next login.
- **Programs started from the desktop stay in the session's scope**, not in
  scopes of their own under `app.slice`: XFCE does not start apps through
  systemd as GNOME does.
- **Desktop Servers created before this build keep the old setup**: the OS
  is the user's, and the image is only its starting point.

### Look

A dark, quiet desktop of our own: a menu bar on top, a dock at the bottom,
windows with a unified title bar. It borrows the layout people know from
macOS but none of Apple's artwork, names or icons; everything is drawn
here or comes from open projects: XFCE's own panel and plugins for the
menu bar, NovaDock for the dock. The whole story (each part, the traps, what we
tried and left out) is in [desktop/README.md](desktop/README.md).

| Part | What | Where |
|---|---|---|
| Widgets | GTK's built-in Adwaita, dark, plus menus with rounded bottom corners (in the user's CSS, which outranks the applications' own) | theme `Ghostdock`: `desktop/rootfs/usr/share/themes/Ghostdock/gtk-3.0/gtk.css` (and `gtk-dark.css`, the same, for applications that ask for a dark variant) |
| Window frames | xfwm4 theme: title bar in Adwaita's toolbar colour, rounded top corners, hairline border, dot buttons on the left (maximize in phosphor). | drawn by `desktop/theme/xfwm4.py` at build time: `Ghostdock` (dark) and `Ghostdock-Light`, each at 1x and 2x (`-xhdpi`) |
| Menu bar | xfce4-panel, dark: the Ghostdock mark (`ghostdock-symbolic`, the applications menu), the active app's menus (xfce4-appmenu-plugin with appmenu-gtk3-module), tray, sound, clock | `xfce4-panel.xml`; its style in `rootfs/etc/skel/.config/gtk-3.0/gtk.css` (the panel's own CSS outranks a theme's) |
| Dock | [NovaDock](https://github.com/novik133/NovaDock) (GPL-3.0), built from a pinned commit with `desktop/novadock.patch`; theme `ghostdock-dark` (`ghostdock` is the light one), a gentle magnification on hover (1.3; measured at no noticeable CPU next to the stream) | `rootfs/usr/share/novadock`, `rootfs/etc/skel/.config/novadock` |
| Desktop menus | with the desktop focused, the menu bar shows Desktop, Files, Documents, Music, Pictures and Video (the appmenu plugin's desktop menus) instead of "xfdesktop" with New and Quit | `rootfs/usr/lib/ghostdock/desktop-menu`, started from `/etc/xdg/autostart` |
| Session | the package's own (xfwm4, xfsettingsd, xfce4-panel, Thunar's daemon, xfdesktop), not saved on exit. NovaDock starts from `/etc/xdg/autostart` | `xfce4-session.xml` |
| Icons, cursor | Papirus-Dark, Adwaita | `xsettings.xml` |
| Fonts | Inter for the interface, JetBrains Mono for code | `xsettings.xml` |
| Desktop icons | the files in `~/Desktop`, nothing else (no Home, File System, Trash or drives) | `xfce4-desktop.xml` |
| Wallpaper | a quiet harbor with the Ghost on the Pier, small, at the end of the deck: night (the default) and dawn | drawn by `desktop/theme/wallpaper.py` at build time |
| Terminal | brand colours: terminal ground, fog text, phosphor cursor | `xfce4-terminal.xml`, padding in `rootfs/etc/skel/.config/gtk-3.0/gtk.css` |
| Browser tab | title "Desktop · Ghostdock" and the brand's tile icon, over Selkies' own | `desktop/web/` (icons copied from `brand/`), applied in the Dockerfile |
| Firefox | dark, no onboarding, Terms of Use prompt, sponsored tiles or bookmarks bar | `rootfs/etc/firefox/policies/policies.json` |

The XFCE settings are system channels in
`desktop/rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml`; a user's own
changes land in their home and win. The light parts (frames, dock theme,
wallpaper) stay in the image for a later light mode that follows the
viewer's system.

- **Scaling.** Selkies reports the browser's pixel ratio as a DPI (192 on a
  Retina screen), which on its own would scale only text.
  `/usr/lib/ghostdock/desktop-bin/xfconf-query`, first on the session's
  PATH, turns it into a window scale (2) plus the remaining DPI, and
  switches the frames to `Ghostdock-xhdpi`. Selkies also resizes the screen
  with the browser window: the panel follows it by itself; the dock follows
  it and restarts itself once when the scale changes (novadock.patch).
- **Compositing** is on, for shadows, rounded corners and the translucent
  menu bar and dock. Measured while dragging a window: about a tenth more
  CPU, next to Selkies' encoder, and the same at idle.

## Trying it locally

Build the images locally. Leave out `UBUNTU_SNAPSHOT` to use the live
archive (an arm64 build of the headless image always does: there is no
snapshot of ubuntu-ports):

```sh
docker build -f images/headless/Dockerfile --build-arg UBUNTU_SNAPSHOT=20261016T000000Z -t gdo-headless images
```

The desktop builds on a headless image (a local tag works; without
`HEADLESS` it is the candidate `ghostdockhq/headless:ubuntu-26.04-rc`), for linux/amd64
only: its Python wheels are x86_64 builds for CPython 3.14. On another machine,
build both images with `--platform linux/amd64`.

```sh
docker build -f images/desktop/Dockerfile --build-arg HEADLESS=gdo-headless -t gdo-desktop images
```

They boot only as a Server: push a build to a registry the instance reads and
create one with `ghostdock vm up --system <ref>`. `validate.sh` runs the
release checks against any Ghostdock instance where the CLI is logged in:
`images/validate.sh <headless|desktop> <image ref>`. It creates a Server from
the image, checks it and deletes it again.
