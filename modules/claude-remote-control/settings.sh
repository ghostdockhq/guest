#!/bin/sh
# Claude Code's settings this module needs, set ahead so nothing asks on a terminal:
#   check-trust, trust    ~/.claude.json projects["<folder>"].hasTrustDialogAccepted: true
#   check-bypass, bypass  ~/.claude/settings.json skipDangerousModePermissionPrompt: true, only
#                         with permission-mode bypassPermissions (otherwise check-bypass passes)
#   check-hooks, hooks    ~/.claude/settings.json hooks UserPromptSubmit and PreToolUse that run
#                         ghostdock-step busy: a prompt, and every tool Claude runs for it, is use
#                         of the VM for 15 minutes (https://docs.ghostdock.ai/vms/sleep), so it does not go to sleep
#                         under a session that works. A hook that fails does nothing.
# Each file is rewritten whole through a temporary file, keeping everything else in it.
set -eu
folder=$(sh "$GHOSTDOCK_MODULE_DIR/folder.sh")
action=${1:?check-trust, trust, check-bypass, bypass, check-hooks or hooks}
case $action in
check-bypass | bypass)
  [ "${GHOSTDOCK_WITH_PERMISSION_MODE:-default}" = bypassPermissions ] || exit 0
  ;;
esac
FOLDER=$folder python3 - "$action" <<'EOF'
import json, os, shlex, sys, tempfile

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

# The hook's command: ghostdock-step on a Server, never in the way of Claude.
reason = "Claude Code is working in " + os.environ["FOLDER"].replace(home, "~", 1)
busy = (
    "/run/ghostdock/bin/ghostdock-step busy --for 15m "
    + shlex.quote(reason)
    + " >/dev/null 2>&1 || true"
)
HOOK_EVENTS = ("UserPromptSubmit", "PreToolUse")


def has_hook(event):
    for entry in data.get("hooks", {}).get(event, []):
        for hook in entry.get("hooks", []):
            if hook.get("command") == busy:
                return True
    return False


if action == "check-trust":
    project = data.get("projects", {}).get(os.environ["FOLDER"], {})
    sys.exit(0 if project.get("hasTrustDialogAccepted") is True else 1)
if action == "check-bypass":
    sys.exit(0 if data.get("skipDangerousModePermissionPrompt") is True else 1)
if action == "check-hooks":
    sys.exit(0 if all(has_hook(event) for event in HOOK_EVENTS) else 1)

if action == "trust":
    data.setdefault("projects", {}).setdefault(os.environ["FOLDER"], {})["hasTrustDialogAccepted"] = True
elif action == "hooks":
    hooks = data.setdefault("hooks", {})
    for event in HOOK_EVENTS:
        # Another folder's or an older text of this module's hook goes; anyone else's stays.
        kept = []
        for entry in hooks.get(event, []):
            entry["hooks"] = [
                h for h in entry.get("hooks", [])
                if not str(h.get("command", "")).startswith("/run/ghostdock/bin/ghostdock-step busy ")
            ]
            if entry["hooks"]:
                kept.append(entry)
        item = {"hooks": [{"type": "command", "command": busy}]}
        if event == "PreToolUse":
            item = {"matcher": "*", **item}
        hooks[event] = kept + [item]
else:
    data["skipDangerousModePermissionPrompt"] = True
os.makedirs(os.path.dirname(path), exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
EOF
