#!/bin/bash
# Prints the Info.plist keys that tell the About window which build this is:
#   build-info-plist.sh <repo-dir>
# One <key>..</key><string>..</string> pair per line, XML-escaped, ready to be appended inside the
# top-level <dict> of the app's Info.plist (Makefile, `app` target). Prints nothing, and succeeds,
# when <repo-dir> is not a git checkout with at least one commit, so a build from a source tarball
# still works. Test: Scripts/test-build-info-plist.sh.
set -uo pipefail

# A GIT_DIR inherited from a surrounding git command would point git at another repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

dir=$(cd "${1:?usage: build-info-plist.sh <repo-dir>}" 2>/dev/null && pwd) || exit 0
git -C "$dir" rev-parse --verify -q HEAD >/dev/null 2>&1 || exit 0

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
emit() { printf '<key>%s</key><string>%s</string>\n' "$1" "$(printf '%s' "$2" | esc)"; }

dirty=false
git -C "$dir" diff --quiet HEAD 2>/dev/null || dirty=true

# A linked worktree has its own git dir, apart from the shared one.
worktree=""
if [ "$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)" != \
     "$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ]; then
  worktree=$(basename "$dir")
fi

emit KCGitDescribe "$(git -C "$dir" describe --tags --always 2>/dev/null)"
emit KCGitBranch "$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
emit KCGitSHA "$(git -C "$dir" rev-parse HEAD 2>/dev/null)"
emit KCGitDirty "$dirty"
emit KCBuildDate "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# A CI runner's checkout path is meaningless on the machine that runs the app: without it the About
# window has no local sources to compare with and leaves the freshness line out.
if [ -z "${CI:-}${GITHUB_ACTIONS:-}" ]; then
  emit KCSourceRepo "$dir"
fi
emit KCWorktree "$worktree"
