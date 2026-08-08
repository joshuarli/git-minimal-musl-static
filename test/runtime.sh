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
    for native_file in "$native_output" "$native_log_output" "$native_plain_log_output"; do
        if grep -a -E -q 'metadata capture failed|incomplete utf-8 byte sequence' "$native_file"; then
            echo "native diff-pretty metadata capture failed" >&2
            exit 1
        fi
    done

    native_empty_log="$test_home/native-empty-log"
    (sleep 1; printf 'q') |
        case "$(uname -s)" in
            Darwin)
                script -q "$native_empty_log" sh -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' log -- no-such-path" \
                >/dev/null
                ;;
            Linux)
                script -q -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' log -- no-such-path" \
                "$native_empty_log" >/dev/null
                ;;
        esac
    if grep -a -F -q "$(printf '\033[?1049h')" "$native_empty_log"; then
        echo "empty native log entered diff-pretty" >&2
        exit 1
    fi

    for i in $(seq 1 32); do
        printf '%s\n' "$i" > quit.txt
        git add quit.txt
        GIT_AUTHOR_NAME=Joshua \
        GIT_AUTHOR_EMAIL=joshua@example.com \
        GIT_COMMITTER_NAME=Joshua \
        GIT_COMMITTER_EMAIL=joshua@example.com \
            git commit -qm "quit-$i"
    done
    native_quit_log="$test_home/native-quit-log"
    (sleep 1; printf 'q') |
        case "$(uname -s)" in
            Darwin)
                script -q "$native_quit_log" sh -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' log" \
                >/dev/null
                ;;
            Linux)
                script -q -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' log" \
                "$native_quit_log" >/dev/null
                ;;
        esac
    quit_commit_count=$(grep -a -c 'commit ' "$native_quit_log" || true)
    test "$quit_commit_count" -lt 32
fi

# Put a UTF-8 lead byte at the end of the adapter's first capture chunk. The
# prefix length is stable for the next commit: the object name has fixed width
# and the author/date fields use the same values and format.
git log -1 > "$test_home/metadata-prefix"
metadata_prefix_bytes=$(LC_ALL=C awk '
    NR <= 4 { total += length($0) + 1 }
    END { print total + 4 }
' "$test_home/metadata-prefix")
metadata_padding_bytes=$((8191 - metadata_prefix_bytes))
test "$metadata_padding_bytes" -gt 0
LC_ALL=C awk -v padding="$metadata_padding_bytes" '
    BEGIN {
        for (i = 0; i < padding; i++)
            printf "a"
        printf "\316\224\n"
    }
' > "$test_home/long-message"
printf '%s\n' long > long.txt
git add long.txt
GIT_AUTHOR_NAME=Joshua \
GIT_AUTHOR_EMAIL=joshua@example.com \
GIT_COMMITTER_NAME=Joshua \
GIT_COMMITTER_EMAIL=joshua@example.com \
    git commit -F "$test_home/long-message" -q

if command -v script >/dev/null 2>&1; then
    delta=$(printf '\316\224')
    git log -1 > "$test_home/boundary-plain"
    boundary_offset=$(LC_ALL=C grep -abo "$delta" "$test_home/boundary-plain" |
        head -1 | cut -d: -f1)
    test "$boundary_offset" = 8191
    native_boundary_log="$test_home/native-boundary-log"
    case "$(uname -s)" in
        Darwin)
            (sleep 1; printf 'q') |
                script -q "$native_boundary_log" sh -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' log -1" \
                >/dev/null
            ;;
        Linux)
            (sleep 1; printf 'q') |
                script -q -c \
                "stty rows 24 cols 80; exec env GIT_PAGER=builtin:diff-pretty TERM=dumb '$git' log -1" \
                "$native_boundary_log" >/dev/null
            ;;
    esac
    if grep -a -E -q 'metadata capture failed|incomplete utf-8 byte sequence' "$native_boundary_log"; then
        echo "native diff-pretty metadata boundary regression" >&2
        exit 1
    fi
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
