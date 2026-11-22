#!/bin/sh
# Installs gh from GitHub's package repository
# (https://github.com/cli/cli/blob/trunk/docs/install_linux.md), so apt keeps it up to date.
set -eu
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  >/etc/apt/sources.list.d/github-cli.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y gh
