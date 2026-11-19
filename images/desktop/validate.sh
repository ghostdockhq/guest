# The desktop's own checks, sourced by images/validate.sh after the checks every OS image has,
# with the VM in $vm and that script's functions (expect, run, fail, and ghostdock).
# The checks are shell text for the VM: its $… expand there, not here.
# shellcheck shell=bash disable=SC2016,SC2154

expect "$vm" "/dev/shm is a tmpfs" tmpfs 'stat -f -c %T /dev/shm'
# The desktop's own units; gdo-apt-lists (headless) runs once and is inactive by design.
expect "$vm" "every desktop unit is active" 0 \
	'systemctl list-units --all --no-legend --state=failed,inactive,activating "gdo-desktop*.service" gdo-xvfb.service gdo-selkies.service | wc -l'
# The desktop is a login session of ghost, as a display manager makes one:
# logind's, of type x11, active.
expect "$vm" "the desktop is an active x11 login session of ghost" "x11 active ghost" \
	'loginctl list-sessions --no-legend | while read -r s _; do [ "$(loginctl show-session "$s" -p Service --value)" = ghostdock-desktop ] || continue; echo "$(loginctl show-session "$s" -p Type --value) $(loginctl show-session "$s" -p State --value) $(loginctl show-session "$s" -p Name --value)"; done'
# The session's Restart and Shut Down ask logind first (polkit, 50-ghostdock.rules).
expect "$vm" "logind lets ghost restart and shut down" 's "yes" s "yes"' \
	'for m in CanReboot CanPowerOff; do busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager $m; done | paste -sd " " -'
# One user manager for the desktop and SSH: an SSH login reaches the
# desktop's PipeWire, whose default sink is the one Selkies streams.
expect "$vm" "ghost's user manager has no failed unit" 0 'systemctl --user --failed --no-legend | wc -l'
# The picture: Selkies captures the display with pixelflux, whose bundled
# FFmpeg needs libva-x11 from the image. Without it the browser waits
# for a stream forever while sound still plays.
expect "$vm" "Selkies' video capture library loads" ok \
	'/opt/selkies/bin/python -c "import pixelflux" && echo ok'
expect "$vm" "Selkies started no capture failure" 0 \
	'sudo journalctl -b -u gdo-selkies --no-pager | grep -c -E "pixelflux library unavailable|Failed to start capture" || true'
# desktop-keyring: a login keyring without a password, unlocked without a prompt ("/").
expect "$vm" "the login keyring unlocks without a prompt" 'aoo 1 "/org/freedesktop/secrets/collection/login" "/"' \
	'busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service Unlock ao 1 /org/freedesktop/secrets/collection/login'
# The desktop's use (input, sound) for gdo-guest, with the
# port the desktop is served on, written every 10 s.
expect "$vm" "the desktop reports its use for idle stop" "port=$(run "$vm" '. /etc/ghostdock/selkies.env && echo "$SELKIES_PORT"') fresh" \
	'systemctl is-active --quiet gdo-desktop-activity && f=/run/ghostdock-desktop/activity && sudo test $(( $(date +%s) - $(sudo stat -c %Y $f) )) -le 30 && echo "$(sudo grep ^port= $f) fresh"'
expect "$vm" "sound is PipeWire, playing to Selkies' sink" "PipeWire output" \
	'pactl info | grep -q "on PipeWire" && echo "PipeWire $(pactl get-default-sink)"'
# ghost comes from the headless image, older than the desktop's /etc/skel.
expect "$vm" "ghost's home has the desktop's per-user files" "ghost ghost" \
	'stat -c %U ~/.config/novadock/config.ini ~/.config/gtk-3.0/gtk.css | tr "\n" " "'
# The port Selkies listens on, and the URL titled Desktop the app made
# from the image's ghostdock.urls.desktop labels: they must agree, or
# the Desktop button opens nothing.
port=$(run "$vm" '. /etc/ghostdock/selkies.env && echo "$SELKIES_PORT"') || fail "no /etc/ghostdock/selkies.env"
urls=$(ghostdock vm url list "$vm" --json)
desktop=$(jq -c '[(.urls // .items // .)[] | select(.title == "Desktop")]' <<<"$urls")
[ "$(jq length <<<"$desktop")" = 1 ] || fail "want one URL titled Desktop, got: $urls"
[ "$(jq -r '.[0].port' <<<"$desktop")" = "$port" ] || fail "desktop URL port $(jq -r '.[0].port' <<<"$desktop"), Selkies listens on $port"
access=$(jq -r '.[0].access' <<<"$desktop")
[ "$access" = organization ] || fail "the desktop URL's access is '$access', not organization"
echo "ok: the app made a private URL titled Desktop on port $port"
# Devices on the private network reach the desktop only through gdo-ingress:
# its port is dropped for 198.18.0.0/15 except gdo-ingress's 198.18.0.0.
expect "$vm" "the desktop's port is closed to private network devices" 1 \
	"sudo nft list table inet gdo_desktop_guard | grep -c 'ip saddr 198.18.0.0/15 ip saddr != 198.18.0.0 tcp dport $port '"
expect "$vm" "the desktop answers on its port" 200 \
	"curl -s -o /dev/null -w '%{http_code}' http://localhost:$port/"
expect "$vm" "Selkies is healthy" 200 \
	"curl -s -o /dev/null -w '%{http_code}' http://localhost:$port/api/health"
# After a 101 the connection stays open, and newer curl waits on it until
# --max-time (exit 28). The status code decides: a failed connect is 000.
expect "$vm" "the stream's websocket upgrades" 101 \
	"curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' http://localhost:$port/api/websockets || true"
