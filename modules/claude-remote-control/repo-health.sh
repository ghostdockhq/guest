#!/bin/sh
# Keeps the folder's git checkout usable after a power-off without a clean shutdown (a host that
# lost power or crashed, a VM forced off), which can leave lock files, empty objects, a broken
# index or an empty branch ref behind. A folder that is not itself a checkout (no .git in it)
# passes: nothing to keep. Remote Control does not wait for it: a failing step warns.
#   check   no stale lock, no empty ref, `git status` works, and the commits and trees HEAD and
#           the refs reach are all there (`git fsck --connectivity-only`, which reads no blob and
#           checks no object's format, so old repositories' legacy objects pass). That fsck runs
#           at most once per boot; its result counts until the next boot or a repair.
#   repair  removes stale locks and empty loose objects, restores an empty branch ref from its
#           reflog, rebuilds a broken index from HEAD (the working tree is never touched, so
#           uncommitted changes stay; staged-only changes are in the kept index.broken-*), and
#           fetches what is missing from origin, at most once per boot; then checks again, and
#           says what it could not repair
set -u
folder=$(sh "$GHOSTDOCK_MODULE_DIR/folder.sh") || exit 1
action=${1:?check or repair}
[ -d "$folder" ] || {
  echo "$folder does not exist" >&2
  exit 1
}
# Only the folder's own checkout: a repository around it (dotfiles in the home) is not this one's.
[ -e "$folder/.git" ] || exit 0
gitdir=$(git -C "$folder" rev-parse --absolute-git-dir 2>/dev/null) || {
  echo "$folder has a .git git cannot read" >&2
  exit 1
}
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/ghostdock/repo-health
key=$(printf '%s' "$folder" | sha256sum | cut -c1-16)
fsck_stamp=$state_dir/$key.fsck
refetch_stamp=$state_dir/$key.refetch
boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)
booted=$(sed -n 's/^btime //p' /proc/stat 2>/dev/null)

# Whether a git runs in the checkout now (its locks are its own, not stale).
git_runs_here() {
  for proc in /proc/[0-9]*; do
    [ "$(cat "$proc/comm" 2>/dev/null)" = git ] || continue
    case $(readlink "$proc/cwd" 2>/dev/null) in
    "$folder" | "$folder"/*) return 0 ;;
    esac
  done
  return 1
}

# Lock files git left when it was cut off: from before this boot, or untouched for 5 minutes,
# while no git runs in the checkout.
stale_locks() {
  git_runs_here && return 0
  {
    find "$gitdir" -maxdepth 1 -name '*.lock' -type f 2>/dev/null
    find "$gitdir/refs" -name '*.lock' -type f 2>/dev/null
  } | while IFS= read -r lock; do
    changed=$(stat -c %Y "$lock" 2>/dev/null) || continue
    now=$(date +%s)
    if { [ -n "$booted" ] && [ "$changed" -lt "$booted" ]; } || [ $((now - changed)) -gt 300 ]; then
      printf '%s\n' "$lock"
    fi
  done
}

empty_refs() {
  find "$gitdir/refs" -type f -size 0 ! -name '*.lock' 2>/dev/null
}

# The connectivity check, once per boot: "<boot> ok" or "<boot> failed" in the stamp.
connected() {
  if [ -f "$fsck_stamp" ]; then
    read -r stamped result <"$fsck_stamp"
    if [ "$stamped" = "$boot" ]; then
      [ "$result" = ok ] && return 0
      echo "git fsck found missing or broken objects at this boot; the repair fetches them" >&2
      return 1
    fi
  fi
  mkdir -p "$state_dir"
  if out=$(git -C "$folder" fsck --connectivity-only --no-dangling --no-progress 2>&1); then
    printf '%s ok\n' "$boot" >"$fsck_stamp"
    return 0
  fi
  printf '%s failed\n' "$boot" >"$fsck_stamp"
  printf '%s\n' "$out" | head -20 >&2
  return 1
}

check() {
  locks=$(stale_locks)
  if [ -n "$locks" ]; then
    echo "Stale git lock files: $locks" >&2
    return 1
  fi
  refs=$(empty_refs)
  if [ -n "$refs" ]; then
    echo "Empty git refs: $refs" >&2
    return 1
  fi
  git -C "$folder" status --porcelain >/dev/null 2>&1 || {
    git -C "$folder" status --porcelain 2>&1 | head -5 >&2
    return 1
  }
  connected
}

repair() {
  rm -f "$fsck_stamp"
  for lock in $(stale_locks); do
    echo "Removing the stale lock $lock"
    rm -f "$lock"
  done
  find "$gitdir/objects" -path "$gitdir/objects/??/*" -type f -size 0 -print -delete 2>/dev/null |
    sed 's/^/Removed the empty object /'
  for ref in $(empty_refs); do
    name=${ref#"$gitdir"/}
    sha=$(tail -n 1 "$gitdir/logs/$name" 2>/dev/null | cut -d' ' -f2)
    if [ -n "$sha" ] && git -C "$folder" cat-file -e "$sha^{commit}" 2>/dev/null; then
      echo "Restoring $name to $sha from its reflog"
      printf '%s\n' "$sha" >"$ref"
    else
      echo "Removing the empty ref $name (no reflog entry to restore it from)"
      rm -f "$ref"
    fi
  done
  if ! git -C "$folder" status --porcelain >/dev/null 2>&1; then
    index=$gitdir/index
    if [ -f "$index" ]; then
      backup="$index.broken-$(date +%Y%m%d%H%M%S)"
      echo "Rebuilding the index from HEAD. Uncommitted changes in your files stay; changes that were only staged are in the broken index, kept as $backup."
      mv "$index" "$backup"
    fi
    git -C "$folder" reset -q --mixed 2>&1 || true
  fi
  if ! git -C "$folder" fsck --connectivity-only --no-dangling --no-progress >/dev/null 2>&1; then
    if [ -f "$refetch_stamp" ] && [ "$(cat "$refetch_stamp")" = "$boot" ]; then
      echo "Already fetched from origin at this boot: not again until the next one" >&2
    elif git -C "$folder" remote get-url origin >/dev/null 2>&1; then
      mkdir -p "$state_dir" && printf '%s\n' "$boot" >"$refetch_stamp"
      echo "Fetching what is missing from origin"
      git -C "$folder" fetch --refetch --quiet origin 2>&1 || git -C "$folder" fetch --quiet origin 2>&1 || true
    fi
  fi
  if check; then
    echo "The checkout in $folder is healthy again"
    return 0
  fi
  echo "Could not repair the checkout in $folder. Nothing in its working tree was changed: copy what you need, then move it away and clone it again." >&2
  return 1
}

case $action in
check) check ;;
repair) repair ;;
*)
  echo "unknown action $action" >&2
  exit 2
  ;;
esac
