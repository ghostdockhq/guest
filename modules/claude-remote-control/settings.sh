#!/bin/sh
# Claude Code's settings this module needs, set ahead so nothing asks on a terminal:
#   check-trust, trust    ~/.claude.json projects["<folder>"].hasTrustDialogAccepted: true
#   check-bypass, bypass  ~/.claude/settings.json skipDangerousModePermissionPrompt: true, only
#                         with permission-mode bypassPermissions (otherwise check-bypass passes)
# Each file is rewritten whole through a temporary file, keeping everything else in it.
set -eu
folder=$(sh "$GHOSTDOCK_MODULE_DIR/folder.sh")
action=${1:?check-trust, trust, check-bypass or bypass}
case $action in
check-bypass | bypass)
  [ "${GHOSTDOCK_WITH_PERMISSION_MODE:-default}" = bypassPermissions ] || exit 0
  ;;
esac
FOLDER=$folder python3 - "$action" <<'EOF'
import json, os, sys, tempfile

action = sys.argv[1]
home = os.path.expanduser("~")
if action.endswith("trust"):
    path = os.path.join(home, ".claude.json")
else:
    path = os.path.join(home, ".claude", "settings.json")
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}

if action == "check-trust":
    project = data.get("projects", {}).get(os.environ["FOLDER"], {})
    sys.exit(0 if project.get("hasTrustDialogAccepted") is True else 1)
if action == "check-bypass":
    sys.exit(0 if data.get("skipDangerousModePermissionPrompt") is True else 1)

if action == "trust":
    data.setdefault("projects", {}).setdefault(os.environ["FOLDER"], {})["hasTrustDialogAccepted"] = True
else:
    data["skipDangerousModePermissionPrompt"] = True
os.makedirs(os.path.dirname(path), exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
EOF
