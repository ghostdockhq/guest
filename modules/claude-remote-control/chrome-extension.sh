#!/bin/sh
# Satisfied without chrome: true, or when Claude in Chrome (fcoeoabgfenejglbffodgkkbkcdhcgfn) is
# installed in one of the login user's Chrome profiles. Whether it is signed in to the same account
# is not visible from here.
[ "${GHOSTDOCK_WITH_CHROME:-false}" = true ] || exit 0
for dir in "$HOME"/.config/google-chrome/*/Extensions/fcoeoabgfenejglbffodgkkbkcdhcgfn; do
  [ -d "$dir" ] && exit 0
done
echo "Claude in Chrome is not installed in the VM's Chrome" >&2
exit 1
