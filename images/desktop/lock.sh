#!/bin/sh
# Regenerates requirements.txt from requirements.in: every package pinned with
# its hashes, wheels only, for the Python and platform of the desktop image
# (Ubuntu 26.04: CPython 3.14, glibc, x86_64). Needs uv.
set -eu
cd "$(dirname "$0")"
uv pip compile requirements.in \
	--python-version 3.14 \
	--python-platform x86_64-manylinux_2_28 \
	--only-binary :all: \
	--generate-hashes \
	--no-header \
	--output-file requirements.txt
