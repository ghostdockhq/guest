# The desktop's look

The requirement module `ghostdock/desktop`: Ghostdock's desktop, which it adds
to a Server and which the desktop image (`ghostdockhq/desktop`) is built from.
`install.sh` installs it (`module.yaml` runs it); how the desktop works is in
images/README.md, *Desktop*.

This page is how the desktop looks the way it does: which parts make it up,
where each one is configured, and the traps we found on the way. The overview
table is in images/README.md, *Look*.

The goal: a dark, quiet desktop that feels at home next to macOS (a menu bar
on top, a dock at the bottom, unified title bars) without pretending to be
macOS. No Apple artwork, names or icons; everything is drawn here or comes
from open projects. It also has to stay cheap: it runs in a microVM without
a GPU, and every frame is encoded for the browser by Selkies.

## The parts

| Part | What | Configured in |
|---|---|---|
| Window manager | xfwm4, with its own compositor on | `rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml` |
| Window frames | our theme `Ghostdock`, drawn by [`theme/xfwm4.py`](theme/xfwm4.py) | the script; `xfwm4.xml` picks it |
| Widgets | GTK's built-in Adwaita, dark, through our theme `Ghostdock` | `rootfs/usr/share/themes/Ghostdock/gtk-3.0/` |
| Menu bar | xfce4-panel with Ubuntu's plugins: applications menu, appmenu (global menu), tray, pulseaudio, clock | `xfce4-panel.xml`; style in `skel-config/gtk-3.0/gtk.css` |
| Desktop menus | the appmenu plugin's own Desktop, Files, Documents, … menus when the desktop is focused | `rootfs/usr/lib/ghostdock/desktop-menu` |
| Dock | [NovaDock](https://github.com/novik133/NovaDock), built from a pinned commit with [`novadock.patch`](novadock.patch) | `rootfs/usr/share/novadock/themes/`, `skel-config/novadock/config.ini` |
| Desktop icons | the files in `~/Desktop` only, without Home, File System, Trash or drives | `xfce4-desktop.xml` |
| Wallpaper | a harbor at night with the Ghost on the Pier, drawn by [`theme/wallpaper.py`](theme/wallpaper.py) | `xfce4-desktop.xml` |
| Icons | Papirus-Dark; our mark `ghostdock-symbolic` in the menu bar | `xsettings.xml`, `rootfs/usr/share/icons/hicolor/` |
| Fonts | Inter (interface), JetBrains Mono (code) | `xsettings.xml` |
| Terminal | xfce4-terminal in brand colours | `xfce4-terminal.xml` |
| Firefox | dark, no first-run screens or sponsored tiles | `rootfs/etc/firefox/policies/policies.json` |
| Browser tab | title "Desktop · Ghostdock", the platform's icons, the sidebar in brand colors | [`web/`](web/), applied by `install.sh`; `gdo-selkies.service` |
| Scaling | an integer window scale from Selkies' DPI | `rootfs/usr/lib/ghostdock/desktop-bin/xfconf-query` |

Everything XFCE reads is a system channel in
`rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/`: a user's own changes land
in their home and win. Per-user files come from `skel-config/`, which `install.sh` puts in `/etc/skel/.config` (`ghost`
comes from the headless image, so `install.sh` copies them into its home
after `rootfs`, without replacing a file `ghost` already has).

## Window frames

[`theme/xfwm4.py`](theme/xfwm4.py) draws every frame piece with Pillow at
install time, at 4x and scaled down for clean edges:

- A 28px title bar in the colour of Adwaita's toolbar, so title bar and
  toolbar read as one header. Rounded top corners (10px), a hairline border,
  a transparent resize margin that lets the compositor's shadow show.
- Dot buttons on the left: close, minimize, and maximize in phosphor (the
  brand's green), with their symbol on hover; grey when the window is
  inactive. The buttons start after the corner piece (`button_offset`, and
  `maximized_offset` for maximized windows), or they paint over the corner.
- Two palettes: `Ghostdock` (dark, the default) and `Ghostdock-Light`, each
  at 1x and 2x (`-xhdpi`). The light ones wait for a light mode.

Bottom corners stay square: an app draws its content right to the bottom
edge, and xfwm4 can only shape its own frame. Rounding every corner would
take picom as the compositor instead of xfwm4's; we stayed with xfwm4
(one process less, no rules to keep).

Compositing is on for shadows, the rounded corners and the translucent menu
bar and dock. Measured while dragging a window: about a tenth more CPU, next
to Selkies' encoder, and the same at idle.

## Widgets and CSS

The theme `Ghostdock` imports GTK's built-in Adwaita dark and adds little
(`gtk.css`; `gtk-dark.css` imports it again for applications that ask for a
dark variant: without it GTK falls back to plain Adwaita and skips ours).

Most of our CSS lives in the **user's** CSS,
`skel-config/gtk-3.0/gtk.css`, because GTK ranks it above an
application's own CSS, which in turn ranks above any theme:

- The menu bar (xfce4-panel styles its widgets itself). Every rule names
  `:backdrop` too: the panel never has the focus, so GTK styles it as a
  background window and Adwaita's dimmed colours would win.
- Menus: square at the top, where they hang from the bar or the pointer,
  rounded at the bottom (6px, which looks like the frames' 10px corners,
  drawn one pixel in), on a soft shadow.
- The terminal's padding.

GTK 3 keeps a column on the left of every menu for check marks and icons,
also in menus without any; that space is GTK's, not ours.

## Menu bar

xfce4-panel with plugins from Ubuntu's packages, in `xfce4-panel.xml`:

1. **Applications menu** behind our mark `ghostdock-symbolic`. The plugin
   shows the icon as an image, without recolouring it, so the SVG is drawn
   light.
2. **appmenu** (xfce4-appmenu-plugin with appmenu-gtk3-module): the active
   application's name and menus, removed from the application's own window
   (`Gtk/ShellShowsMenubar`, `Gtk/Modules` in `xsettings.xml`). Firefox keeps
   its own menus. The menus' letters are underlined until the bar's first
   click: GTK shows mnemonics until a window has had a key press.
3. Separator (expanding), **tray**, **pulseaudio**, **clock**
   (`%a %b %-d  %H:%M`).

With the desktop focused, the appmenu plugin would show "xfdesktop" with New
and Quit: it treats a desktop window that names a GTK application bus as an
ordinary application. [`desktop-menu`](rootfs/usr/lib/ghostdock/desktop-menu)
(from `/etc/xdg/autostart`) removes that name from xfdesktop's desktop
windows, again whenever the window list changes, and the plugin shows its
desktop menus instead: Desktop (its settings and the system's), Files,
Documents, Music, Pictures, Video. The plugin reads a window only when the
active window changes, and at login the desktop is often active before the
name is gone, so the script then sets the active window to None for a second
and back to make the plugin look again.

Ubuntu's plugin crashed on every file in those menus (it handed its launcher
the wrong object), so the image builds the same release from source with
[`appmenu.patch`](appmenu.patch) and replaces only the plugin's library,
diverted with `dpkg-divert` so an `apt upgrade` in a VM keeps it. Its
Desktop Settings and System Settings follow `XDG_CURRENT_DESKTOP`, which
`desktop.env` sets to `XFCE`, as a display manager would from
`xfce.desktop`. A file opens in its type's default application; with
none (a video: there is no player), nothing happens.

The session (`xfce4-session.xml`) is the package's own, not saved on exit,
so every start is the same.

## Dock

[NovaDock](https://github.com/novik133/NovaDock) (GPL-3.0, Vala), built in
`install.sh` from a pinned commit (tarball by checksum)
with [`novadock.patch`](novadock.patch), and started from
`/etc/xdg/autostart`:

- Selkies resizes the X screen whenever the browser window changes size: the
  patch places the dock again once the monitors have settled, and skips
  placing it while the screen has no monitor.
- When a browser first connects, the window scale changes together with the
  screen size, and GTK 3 keeps the old buffer: the patch restarts the dock
  once on a new scale.
- The launchpad uses a full-colour icon (`applications-all`): the dock draws
  icons as images, so a symbolic one would stay dark.

Our themes are `ghostdock-dark` (in use) and `ghostdock` (light), in
`rootfs/usr/share/novadock/themes/`. The config pins Files, Terminal,
Firefox and Mousepad, keeps the trash, drops "show desktop", and magnifies
icons 1.3x on hover (no measurable CPU next to the stream).

## Wallpaper

[`theme/wallpaper.py`](theme/wallpaper.py) draws two at install time, 3840x2160:
a quiet sea at night (the default) and at dawn, with a long pier from the
right and, at its end, the ghost from the mark (docs/brand.md, "Ghost on the
Pier"). The ghost is about 2% of the width, flat, in the mark's geometry and
colours: a detail to find, not a logo to look at. Large soft shapes and few
edges keep it cheap to stream; a little noise keeps the gradients from
banding. xfdesktop keys the wallpaper by monitor name, so `xfce4-desktop.xml`
sets it for Selkies' monitor (`selkies-primary`) and for Xvfb's (`screen`).

## Scaling

Selkies reports the browser's pixel ratio as a DPI (192 on a Retina screen)
by calling `xfconf-query` with the session's environment. A DPI alone scales
only text. `/etc/ghostdock/desktop.env` puts
[`desktop-bin/`](rootfs/usr/lib/ghostdock/desktop-bin/xfconf-query) first on
the session's PATH, and its `xfconf-query` turns the DPI into a window scale
(2) plus the remaining DPI (96), divides the cursor size by the scale, and
switches xfwm4 between `Ghostdock` and `Ghostdock-xhdpi`. The panel follows
the scale by itself; the dock restarts once (see above).

## Browser tab

Selkies' page would show "Selkies", its pink and violet theme and its logo.
What we change:

- **Tab title and icons:** [`web/`](web/) holds our `manifest.json` (the
  page takes the tab title from it) and the platform's icons, linked as the
  app links them (`app/app.vue`): `icon.svg` (brand `favicon.svg`, which
  follows the tab bar's light or dark), `favicon-32.png`, `favicon.ico`,
  `apple-touch-icon.png` and `icon-512.png`. They are copies of `brand/`,
  because the image build only sees `images/`;
  `tests/nuxt/images/desktop-web-icons.test.ts` fails when they differ.
- **Sidebar colors:** `web/ghostdock.css`, linked after Selkies' stylesheet,
  sets Selkies' theme variables to brand colors: night grounds, fog text,
  the phosphor accent (550-ish greens on light).
- **Sidebar title and logo:** Selkies settings in `gdo-selkies.service`:
  `SELKIES_UI_TITLE=Ghostdock`, `SELKIES_UI_SHOW_LOGO=false` (the logo is
  drawn inside Selkies' bundle, so it is hidden rather than replaced).

`install.sh` copies `web/` over Selkies' files, rewrites the links in
`index.html` and fails the build when any of them is not where it expects.
Selkies serves only the files present when it starts: a file added later
answers 404 until `gdo-selkies` restarts.

## What we tried and left out

- **WhiteSur and MacTahoe** (GTK, icon and cursor themes): copies of Apple's
  look, icons (a Finder face) and artwork, with an Apple logo as the
  "start" icon. Replaced by Adwaita, Papirus and our own frames.
- **Plank** as the dock: crisp, but it stays where it was when Selkies
  resizes the screen.
- **NovaBar** as the menu bar: it needed a patched source build to fit a
  VM (resizes, scale, indicators for networks, Bluetooth and batteries
  the VM does not have). xfce4-panel does the same from Ubuntu's
  packages.
- **Windowck** (a maximized window's buttons and title on the menu bar, with
  the title bar hidden): it works, but we preferred maximized windows with
  their own title bar.
- **picom** for rounded bottom corners: see Window frames.

## Changing the look

Build and run it locally as in [../README.md](../README.md#trying-it-locally);
the window frames and wallpapers change in `theme/*.py`, everything else in
`rootfs/`. To try a setting in a running desktop first, run it over SSH: an
SSH login shares the desktop's session bus ([The login
session](../README.md#the-login-session)), for example:

```sh
ghostdock vm ssh <vm> -- xfconf-query -c xfwm4 -p /general/theme -s Ghostdock-Light
```

The CSS in `/home/ghost/.config/gtk-3.0/gtk.css` applies to applications
started after a change; `xfce4-panel -r` restarts the menu bar.
