#!/bin/sh
# Prints the folder (with: folder) as an absolute path: a leading ~/ is the login user's home, also
# when this runs as root.
set -eu
folder=${GHOSTDOCK_WITH_FOLDER:?with: folder is required}
case $folder in
"~" | "~/"*)
  user=${GHOSTDOCK_LOGIN_USER:-$(id -un)}
  home=$(getent passwd "$user" | cut -d: -f6)
  folder="$home${folder#\~}"
  ;;
esac
case $folder in
/*) ;;
*)
  echo "with: folder must be an absolute path or start with ~/, not $folder" >&2
  exit 1
  ;;
esac
printf '%s\n' "${folder%/}"
