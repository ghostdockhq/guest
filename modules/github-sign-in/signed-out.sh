#!/bin/sh
# Satisfied when gh holds no sign-in of its own for the host. A token linked at create (GH_TOKEN)
# is Ghostdock's to retire with the VM, not gh's, so it does not count.
! env -u GH_TOKEN -u GITHUB_TOKEN gh auth status --hostname "${GHOSTDOCK_WITH_HOST:-github.com}" \
  >/dev/null 2>&1
