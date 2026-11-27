# Files the person should open

The person follows these sessions through Remote Control (claude.ai or the Claude app). Its file
viewer opens only files inside the session's working directory: a link to `/tmp`, a scratch folder
or any other path outside it shows "Can't read this file".

- Write what the person should read or open (drafts, reports, screenshots, logs to look at) to
  `.claude/out/` in the working directory, and link that path. Keep scratch work elsewhere.
- A file that exists outside the working directory is copied into `.claude/out/` before it is
  linked.
- `.claude/out/` is never committed: when `git check-ignore -q .claude/out/x` fails, add
  `.claude/out/` to `$(git rev-parse --git-common-dir)/info/exclude` (local, no commit).
- Short text (an issue body, a message to paste) also goes in the reply itself.
