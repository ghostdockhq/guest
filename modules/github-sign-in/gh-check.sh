#!/bin/sh
# Satisfied when gh is at least 2.60. Ubuntu's own (2.46 on 24.04) asks interactive questions while
# it signs in, with no terminal to answer them.
v=$(gh --version 2>/dev/null | sed -n 's/^gh version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')
[ -n "$v" ] || exit 1
# shellcheck disable=SC2086 # split "major minor"
set -- $v
[ "$1" -gt 2 ] || { [ "$1" -eq 2 ] && [ "$2" -ge 60 ]; }
