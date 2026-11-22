#!/bin/sh
# Downloads Google Chrome from Google and installs it. Its package adds Google's repository to apt,
# so apt keeps it up to date from then on.
set -eu
arch=$(dpkg --print-architecture)
if [ "$arch" != amd64 ]; then
  echo "Google publishes Chrome for Linux on amd64 only; this VM is $arch." >&2
  exit 1
fi
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
curl -fsSL -o "$dir/google-chrome.deb" \
  https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y "$dir/google-chrome.deb"
