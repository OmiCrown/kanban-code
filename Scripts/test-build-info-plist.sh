#!/bin/bash
# Test for Scripts/build-info-plist.sh: builds throwaway repos and checks the plist fragment.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/build-info-plist.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
has_fixed() { grep -qF -- "$2" <<<"$1" || fail "$3 (wanted: $2)"; }
has_regex() { grep -qE -- "$2" <<<"$1" || fail "$3 (wanted /$2/)"; }

# Environment variables set by a surrounding git command would point git at another repo.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

mkdir "$T/main"
g -C "$T/main" init -q -b main
echo a > "$T/main/f"
g -C "$T/main" add f
g -C "$T/main" commit -q -m first
g -C "$T/main" checkout -q -b 'feat/a&b'

out=$("$SCRIPT" "$T/main")
has_fixed "$out" '<key>KCGitBranch</key><string>feat/a&amp;b</string>' "branch is XML-escaped"
has_fixed "$out" '<key>KCGitDirty</key><string>false</string>' "clean tree is not dirty"
has_fixed "$out" '<key>KCWorktree</key><string></string>' "main checkout has an empty worktree"
has_regex "$out" '<key>KCGitSHA</key><string>[0-9a-f]{40}</string>' "full SHA"
has_regex "$out" '<key>KCGitDescribe</key><string>[^<]+</string>' "describe"
has_regex "$out" '<key>KCBuildDate</key><string>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z</string>' "UTC build date"
has_regex "$out" '<key>KCSourceRepo</key><string>[^<]*/main</string>' "source repo path"

cat > "$T/wrapped.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>$out</dict></plist>
EOF
plutil -lint "$T/wrapped.plist" >/dev/null || fail "output is not a valid plist"

touch "$T/main/untracked"
has_fixed "$("$SCRIPT" "$T/main")" '<key>KCGitDirty</key><string>false</string>' "untracked files do not make a build dirty"

echo x >> "$T/main/f"
has_fixed "$("$SCRIPT" "$T/main")" '<key>KCGitDirty</key><string>true</string>' "a changed tracked file makes a build dirty"
g -C "$T/main" checkout -q -- f

g -C "$T/main" worktree add -q "$T/wt1" -b wtbranch
wt=$("$SCRIPT" "$T/wt1")
has_fixed "$wt" '<key>KCWorktree</key><string>wt1</string>' "linked worktree is named"
has_fixed "$wt" '<key>KCGitBranch</key><string>wtbranch</string>' "worktree branch"

mkdir "$T/plain"
[ -z "$("$SCRIPT" "$T/plain")" ] || fail "a folder that is not a git checkout prints nothing"

mkdir "$T/unborn"
g -C "$T/unborn" init -q -b main
[ -z "$("$SCRIPT" "$T/unborn")" ] || fail "a repo without commits prints nothing"

echo "PASS: build-info-plist"
