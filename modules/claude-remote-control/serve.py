#!/usr/bin/env python3
"""Runs `claude remote-control` for the claude-remote-control service (run.sh starts it).

- In a terminal of its own: the first run asks "Enable Remote Control? (y/n)" once, and a service
  has nobody to answer, so this answers y: once, and only in the run's first minute. Choosing
  the template or the module is choosing Remote Control for the Claude account the VM is signed
  in with; the question is asked once per login user.
- What claude prints goes on to the journal (journalctl -u claude-remote-control).
- A login claude.ai refused: when claude prints one of Claude Code's definitive lines for it
  (rejected, expired, revoked, signed out, not logged in; never a failed refresh, which a network
  blip causes) and then stops by itself, or is still running 30 s later, the refusal counts when
  `claude auth status` says signed out, or when the previous run ended the same way within the
  hour (a revoked login still reads as signed in on disk, and fails again at once). Then this
  writes ~/.claude/ghostdock/login-rejected, which ghostdock/claude-sign-in's check reads, so the
  VM's setup asks for a new sign-in; the next start waits until a sign-in wrote a newer
  ~/.claude/.credentials.json, and Remote Control is back without anyone restarting it. The same
  words in a session's output, with claude still serving and signed in, change nothing.
"""

import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
STATE = os.path.join(HOME, ".claude", "ghostdock")
MARKER = os.path.join(STATE, "login-rejected")
SEEN = os.path.join(STATE, "login-refusal-seen")
CREDENTIALS = os.path.join(HOME, ".claude", ".credentials.json")
WAIT_SECONDS = float(os.environ.get("CLAUDE_REMOTE_CONTROL_LOGIN_POLL", "15"))
CONFIRM_SECONDS = float(os.environ.get("CLAUDE_REMOTE_CONTROL_REFUSAL_GRACE", "30"))
ANSWER_WITHIN_SECONDS = 60
SEEN_COUNTS_SECONDS = 3600

ANSI = re.compile(rb"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][0-9A-Za-z]|\r")
ENABLE = re.compile(rb"Enable Remote Control\?\s*\(y/n\)", re.IGNORECASE)
# Claude Code's own definitive lines for a login claude.ai no longer takes
# (code.claude.com/docs/en/errors: "Remote Control couldn't refresh your login", "Login expired",
# "OAuth token revoked or expired", "Remote Control requires a claude.ai subscription"). Not
# "OAuth token refresh failed", "OAuth token unavailable" or "JWT refresh failed", which a network
# blip can cause, nor "Your login expires in 3 days", a warning while the login works.
REJECTED = re.compile(
    rb"Remote Control disconnected \S+ (?:Claude\.ai login (?:expired|was rejected)|Signed out of Claude)"
    rb"|(?:Login expired|Login reached its time limit|OAuth token revoked) \S+ Please run /login"
    rb"|You must be logged in to use Remote Control",
    re.IGNORECASE,
)


def log(text):
    sys.stdout.write(f"[ghostdock] {text}\n")
    sys.stdout.flush()


def mtime(path):
    try:
        return os.path.getmtime(path)
    except OSError:
        return None


def newer_than_login(path):
    """Whether a mark at path is newer than the login on disk."""
    marked = mtime(path)
    if marked is None:
        return False
    signed_in = mtime(CREDENTIALS)
    return signed_in is None or marked >= signed_in


def signed_out():
    try:
        return subprocess.run(
            ["claude", "auth", "status"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        ).returncode != 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def seen_before():
    """Whether the previous run ended with a refusal too, within the hour, since the last sign-in."""
    marked = mtime(SEEN)
    return (
        marked is not None
        and time.time() - marked < SEEN_COUNTS_SECONDS
        and newer_than_login(SEEN)
    )


def write(path, text):
    os.makedirs(STATE, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text + "\n")
    os.replace(tmp, path)


def refusal_counts(said):
    """Whether a refusal claude printed counts; records it for the next run when not yet."""
    if signed_out() or seen_before():
        write(MARKER, said)
        try:
            os.remove(SEEN)
        except OSError:
            pass
        return True
    write(SEEN, said)
    return False


def wait_for_login():
    if not newer_than_login(MARKER):
        return
    log("claude.ai refused this VM's login: waiting for a new sign-in (the VM's setup asks for it)")
    while newer_than_login(MARKER):
        time.sleep(WAIT_SECONDS)
    log("signed in again: starting Remote Control")


def main(args):
    wait_for_login()
    started = time.monotonic()
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("claude", ["claude", "remote-control", *args])
    try:
        import fcntl
        import termios

        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
    except OSError:
        pass

    stopping = []

    def forward(signum, _frame):
        try:
            os.kill(pid, signum)
        except ProcessLookupError:
            pass

    def stop(signum, frame):
        # systemd stops the service (a shutdown, a restart): no refusal to read into the exit.
        stopping.append(signum)
        forward(signum, frame)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    seen = b""
    status = None
    may_answer = True
    refused = None  # (what claude said, when)
    marked = False
    while True:
        if refused and not marked and time.monotonic() - refused[1] >= CONFIRM_SECONDS:
            if refusal_counts(refused[0]):
                marked = True
                log(f"claude.ai refused the login ({refused[0]}): stopping until a new sign-in")
                forward(signal.SIGTERM, None)
            else:
                log(f"claude printed '{refused[0]}' but is still signed in: going on")
                refused = None
        try:
            ready, _, _ = select.select([fd], [], [], 1.0)
        except InterruptedError:
            continue
        if not ready:
            done, waited = os.waitpid(pid, os.WNOHANG)
            if done:
                status = waited
                break
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        sys.stdout.buffer.write(chunk)
        sys.stdout.flush()
        seen = (seen + ANSI.sub(b"", chunk))[-8192:]
        if may_answer:
            if time.monotonic() - started > ANSWER_WITHIN_SECONDS:
                may_answer = False  # the question comes first or not at all
            elif ENABLE.search(seen):
                os.write(fd, b"y\r")
                may_answer = False
                log('answered "Enable Remote Control?" with y')
        if refused is None and not marked:
            m = REJECTED.search(seen)
            if m:
                refused = (m.group(0).decode("utf-8", "replace"), time.monotonic())
                seen = b""
    if status is None:
        try:
            _, status = os.waitpid(pid, 0)
        except ChildProcessError:
            status = 0
    code = os.waitstatus_to_exitcode(status)
    if refused and not marked and not stopping:
        # claude stopped by itself after saying the login was refused.
        if refusal_counts(refused[0]):
            marked = True
            log(f"claude.ai refused the login ({refused[0]}): waiting for a new sign-in")
        else:
            log(f"claude stopped after '{refused[0]}' but is still signed in: starting again")
    if marked:
        return 0
    return code if code >= 0 else 128 - code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
