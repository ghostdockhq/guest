#!/bin/sh
# The systemd service that runs Remote Control as the login user (bypass permissions refuses root).
# A system unit with User= rather than a user unit: it starts at boot without a login session or
# lingering, and stops cleanly at shutdown. Its actions:
#   check          the unit and its script are what this module writes, enabled and running
#   install        writes them, then enables and (re)starts the service
#   check-removed  neither is left
#   remove         stops and disables the service, and deletes both
set -eu
unit=/etc/systemd/system/claude-remote-control.service
lib=/usr/local/lib/ghostdock/claude-remote-control
action=${1:?check, install, check-removed or remove}

render() {
  user=${GHOSTDOCK_LOGIN_USER:?the login user is not known}
  home=$(getent passwd "$user" | cut -d: -f6)
  folder=$(sh "$GHOSTDOCK_MODULE_DIR/folder.sh") || return 1
  # What goes into the unit file: a known permission mode, and a folder systemd reads as written
  # (no line break, no % specifier, no control character).
  case ${GHOSTDOCK_WITH_PERMISSION_MODE:-default} in
  default | acceptEdits | plan | auto | dontAsk | bypassPermissions) ;;
  *)
    echo "permission-mode must be default, acceptEdits, plan, auto, dontAsk or bypassPermissions, not ${GHOSTDOCK_WITH_PERMISSION_MODE:-}" >&2
    return 1
    ;;
  esac
  case ${GHOSTDOCK_WITH_CHROME:-false} in
  true | false) ;;
  *)
    echo "chrome must be true or false" >&2
    return 1
    ;;
  esac
  if [ "$(printf '%s' "$folder" | tr -d '[:cntrl:]%\\')" != "$folder" ]; then
    echo "The folder may not hold a line break, a control character, % or \\: $folder" >&2
    return 1
  fi
  cat <<EOF
# Written by the Ghostdock module ghostdock/claude-remote-control.
[Unit]
Description=Claude Remote Control in $folder
After=network-online.target
Wants=network-online.target

[Service]
User=$user
WorkingDirectory=$folder
Environment=HOME=$home
Environment=CLAUDE_REMOTE_CONTROL_PERMISSION_MODE=${GHOSTDOCK_WITH_PERMISSION_MODE:-default}
Environment=CLAUDE_REMOTE_CONTROL_CHROME=${GHOSTDOCK_WITH_CHROME:-false}
ExecStart=$lib/run.sh
Restart=always
RestartSec=10
KillMode=mixed
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF
}

case $action in
check)
  render | cmp -s - "$unit"
  cmp -s "$GHOSTDOCK_MODULE_DIR/run.sh" "$lib/run.sh"
  cmp -s "$GHOSTDOCK_MODULE_DIR/serve.py" "$lib/serve.py"
  systemctl is-enabled --quiet claude-remote-control
  systemctl is-active --quiet claude-remote-control
  ;;
install)
  rendered=$(render) || exit 1
  install -d -m 0755 "$lib"
  install -m 0755 "$GHOSTDOCK_MODULE_DIR/run.sh" "$lib/run.sh"
  install -m 0644 "$GHOSTDOCK_MODULE_DIR/serve.py" "$lib/serve.py"
  printf '%s\n' "$rendered" >"$unit.tmp"
  mv "$unit.tmp" "$unit"
  systemctl daemon-reload
  systemctl enable claude-remote-control
  systemctl restart claude-remote-control
  ;;
check-removed)
  [ ! -e "$unit" ] && [ ! -e "$lib" ]
  ;;
remove)
  systemctl disable --now claude-remote-control 2>/dev/null || true
  rm -rf "$unit" "$lib"
  systemctl daemon-reload
  ;;
*)
  echo "unknown action $action" >&2
  exit 2
  ;;
esac
