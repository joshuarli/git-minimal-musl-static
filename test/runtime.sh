#!/bin/sh
set -eu

bin_dir=${GIT_BIN_DIR:-/usr/local/bin}
git="$bin_dir/git"
expected_exec_path=${GIT_EXPECTED_EXEC_PATH:-$bin_dir}

test -x "$git"
test "$("$git" --version)" = "git version 2.55.0"
test "$("$git" --exec-path)" = "$expected_exec_path"

check_linkage() {
    case "$(uname -s)" in
        Linux)
            test -z "$(ldd "$1" 2>&1 | grep -F '=>' || true)"
            ;;
        Darwin)
            test -z "$(otool -L "$1" | sed '1d' | awk '$1 !~ /^\/(usr\/lib|System\/Library)\// { print $1 }')"
            ;;
        *)
            echo "unsupported runtime: $(uname -s)" >&2
            exit 1
            ;;
    esac
}

check_linkage "$git"
check_linkage "$bin_dir/git-shell"

test -x "$bin_dir/git-shell"
test ! -L "$bin_dir/git-shell"
for helper in git-upload-archive git-upload-pack git-receive-pack; do
    test -x "$bin_dir/$helper"
    test -L "$bin_dir/$helper"
done

test ! -e "$bin_dir/git-cvsserver"
test ! -e "$bin_dir/git-lfs"
test ! -e "$bin_dir/git-filter-repo"
test ! -e "$bin_dir/git-remote-http"
test ! -e "$bin_dir/git-remote-https"

test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT HUP INT TERM
export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
export PATH="$bin_dir:$PATH"
mkdir -p "$XDG_CONFIG_HOME/git"
: > "$XDG_CONFIG_HOME/git/config"

git config --global user.name "Joshua Li"
git config --global user.email joshuarli98@gmail.com
test "$(git config --global --get user.name)" = "Joshua Li"
test "$(git config --global --get user.email)" = joshuarli98@gmail.com
test -f "$XDG_CONFIG_HOME/git/config"

repo="$test_home/repo"
mkdir "$repo"
repo=$(cd "$repo" && pwd -P)
cd "$repo"
git init -q --template=
printf '%s\n' hello > hello.txt
git add hello.txt
GIT_AUTHOR_NAME=Joshua \
GIT_AUTHOR_EMAIL=joshua@example.com \
GIT_COMMITTER_NAME=Joshua \
GIT_COMMITTER_EMAIL=joshua@example.com \
    git commit -qm initial

printf '%s\n' changed > hello.txt
git add hello.txt
GIT_AUTHOR_NAME=Joshua \
GIT_AUTHOR_EMAIL=joshua@example.com \
GIT_COMMITTER_NAME=Joshua \
GIT_COMMITTER_EMAIL=joshua@example.com \
    git commit -qm changed

# The native pager needs a terminal, so keep this focused semantic-path check
# optional for minimal runtime images that do not ship a PTY driver. All
# other runtime commands continue to exercise the ordinary byte path
# everywhere.
if command -v script >/dev/null 2>&1; then
    native_output="$test_home/native-show"
    native_log_output="$test_home/native-log"
    native_plain_log_output="$test_home/native-plain-log"
    case "$(uname -s)" in
        Darwin)
            (sleep 1; printf 'q') |
                script -q "$native_output" sh -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' show HEAD" \
                >/dev/null
            (sleep 1; printf 'q') |
                script -q "$native_log_output" sh -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' log -p -2" \
                >/dev/null
            (sleep 1; printf 'q') |
                script -q "$native_plain_log_output" sh -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' log -2" \
                >/dev/null
            ;;
        Linux)
            (sleep 1; printf 'q') |
                script -q -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' show HEAD" \
                "$native_output" >/dev/null
            (sleep 1; printf 'q') |
                script -q -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' log -p -2" \
                "$native_log_output" >/dev/null
            (sleep 1; printf 'q') |
                script -q -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' log -2" \
                "$native_plain_log_output" >/dev/null
            ;;
    esac
    grep -a -q 'Δ ' "$native_output"
    grep -a -q 'Δ ' "$native_log_output"
    grep -a -q 'diff-pretty' "$native_plain_log_output"
fi

branch=$(git branch --show-current)
test -n "$branch"
git rev-parse --is-inside-work-tree
test "$(git rev-parse --show-toplevel)" = "$repo"
git show-ref --verify --quiet "refs/heads/$branch"
git branch --merged "$branch"
test -z "$(git remote)"
git fsck --no-dangling --no-progress
git pack-refs --all
git rerere gc
git worktree prune
git reflog expire --expire=90.days --expire-unreachable=90.days --all
git gc --quiet
git repack -d --geometric=2 --no-write-bitmap-index --quiet
git prune
git commit-graph write --reachable --changed-paths
git multi-pack-index write --bitmap
test -z "$(git status --short)"
