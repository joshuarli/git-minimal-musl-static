#!/bin/sh
set -eu

version=2.55.0
archive_url="https://www.kernel.org/pub/software/scm/git/git-$version.tar.xz"
archive_sha256=457fdb04dc8728e007d4688695e6912e6f680727920f2a40bf11eacc17505357

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
source_parent="$repo_root/src"
source_dir="$source_parent/git-$version"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/git-minimal-source.XXXXXX")
integration_dir="$work_dir/diff-pretty-integration"

trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

archive="$work_dir/git-$version.tar.xz"
staged_dir="$work_dir/unpack/git-$version"

command -v curl >/dev/null
command -v shasum >/dev/null
command -v tar >/dev/null
command -v awk >/dev/null

curl --fail --location --retry 3 --output "$archive" "$archive_url"
printf '%s  %s\n' "$archive_sha256" "$archive" | shasum -a 256 -c -
mkdir -p "$work_dir/unpack"
tar -xJf "$archive" -C "$work_dir/unpack"
test -f "$staged_dir/Makefile"

# These headers are the only build metadata normally generated from the
# Documentation tree. Generate them while the complete release archive is
# still present, then keep the generated snapshots with the trimmed source.
mkdir -p "$staged_dir/.depend"
sh "$staged_dir/tools/generate-configlist.sh" \
    "$staged_dir" "$staged_dir/config-list.h" \
    "$staged_dir/.depend/config-list.h.d"
sh "$staged_dir/tools/generate-cmdlist.sh" \
    "$staged_dir" "$staged_dir/command-list.h"
sh "$staged_dir/tools/generate-hooklist.sh" \
    "$staged_dir" "$staged_dir/hook-list.h"

# The generated command and hook metadata is checked in below, so those
# Makefile rules must not try to revisit Documentation after it is removed.
awk '
    /^command-list\.h: tools\/generate-cmdlist\.sh/ {
        print "# command-list.h is a checked-in snapshot for this trimmed tree."
        print "command-list.h:"
        skip_command = 1
        next
    }
    skip_command && /^hook-list\.h:/ {
        skip_command = 0
    }
    skip_command { next }
    /^hook-list\.h: tools\/generate-hooklist\.sh/ {
        print "# hook-list.h is a checked-in snapshot for this trimmed tree."
        print "hook-list.h:"
        skip_hook = 1
        next
    }
    skip_hook && /^SCRIPT_DEFINES/ {
        skip_hook = 0
    }
    skip_hook { next }
    { print }
' "$staged_dir/Makefile" > "$work_dir/Makefile"
mv "$work_dir/Makefile" "$staged_dir/Makefile"

awk '
    /^## gitweb\/Makefile inclusion:/ {
        print "# gitweb is omitted from this trimmed tree."
        skip_gitweb = 1
        next
    }
    skip_gitweb && /^### Installation rules/ {
        skip_gitweb = 0
    }
    skip_gitweb { next }
    { print }
' "$staged_dir/Makefile" > "$work_dir/Makefile"
mv "$work_dir/Makefile" "$staged_dir/Makefile"

# Keep the C sources, Makefile, generator tools, and metadata needed by the
# selected production targets. Everything below is outside that build surface.
for path in \
    .cirrus.yml \
    .editorconfig \
    .github \
    .gitattributes \
    .gitignore \
    .gitmodules \
    .gitlab-ci.yml \
    .mailmap \
    .tsan-suppressions \
    ci \
    contrib \
    Documentation \
    git-gui \
    gitk-git \
    gitweb \
    mergetools \
    oss-fuzz \
    perl \
    po \
    RelNotes \
    subprojects \
    t \
    templates; do
    rm -rf "$staged_dir/$path"
done

rm -rf "$staged_dir/.depend"

# Keep the checked-in native diff-pretty overlay while replacing the generated
# Git source tree below. The overlay is deliberately limited to the small Git
# integration edits and adapter; all other source files still come from
# the verified release archive.
if test -f "$source_dir/diff-pretty.c"; then
    mkdir -p "$integration_dir"
    for file in Makefile diff.c pager.c builtin/log.c log-tree.c diff-pretty.c diff-pretty-integration.h; do
        mkdir -p "$integration_dir/$(dirname "$file")"
        cp "$source_dir/$file" "$integration_dir/$file"
    done
fi

rm -f \
    "$staged_dir/Cargo.toml" \
    "$staged_dir/build.rs" \
    "$staged_dir/daemon.c" \
    "$staged_dir/git-curl-compat.h" \
    "$staged_dir/http-backend.c" \
    "$staged_dir/http-fetch.c" \
    "$staged_dir/http-push.c" \
    "$staged_dir/http-walker.c" \
    "$staged_dir/http.c" \
    "$staged_dir/imap-send.c" \
    "$staged_dir/remote-curl.c" \
    "$staged_dir/scalar.c" \
    "$staged_dir/sh-i18n--envsubst.c"

for file in \
    "$staged_dir"/git-*.perl \
    "$staged_dir"/git-*.py \
    "$staged_dir"/git-*.sh; do
    test -e "$file" || continue
    rm -f "$file"
done

rm -rf "$source_dir"
mkdir -p "$source_parent"
mv "$staged_dir" "$source_dir"

if test -d "$integration_dir"; then
    cp -R "$integration_dir"/. "$source_dir"/
fi

printf 'Wrote trimmed Git %s source to %s\n' "$version" "$source_dir"
