#!/bin/sh
set -eu

if test "$#" -ne 2; then
	printf 'usage: %s TARGET CACHE_ROOT\n' "$0" >&2
	exit 2
fi

target=$1
cache_root=$2
repo=joshuarli/diff-pretty
asset="diff-pretty-ffi-$target.tar.gz"
api_url="https://api.github.com/repos/$repo/releases?per_page=100"
cache_dir="$cache_root/$target"

case "$target" in
	''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*)
		echo "invalid diff-pretty target: $target" >&2
		exit 2
		;;
esac

if test -s "$cache_dir/include/diff_pretty.h" \
	&& test -s "$cache_dir/lib/libdiff_pretty_ffi.a" \
	&& test -f "$cache_dir/manifest" \
	&& test "$(awk -F= '$1 == "target" { print $2; exit }' "$cache_dir/manifest")" = "$target"; then
	echo "Using cached diff-pretty FFI package for $target"
	exit 0
fi

command -v curl >/dev/null || { echo 'curl is required to download diff-pretty FFI artifacts' >&2; exit 1; }
command -v tar >/dev/null || { echo 'tar is required to unpack diff-pretty FFI artifacts' >&2; exit 1; }
command -v awk >/dev/null || { echo 'awk is required to verify diff-pretty FFI artifacts' >&2; exit 1; }

if command -v shasum >/dev/null; then
	sha256() { shasum -a 256 "$1" | awk '{ print $1 }'; }
elif command -v sha256sum >/dev/null; then
	sha256() { sha256sum "$1" | awk '{ print $1 }'; }
else
	echo 'shasum or sha256sum is required to verify diff-pretty FFI artifacts' >&2
	exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/diff-pretty-ffi.XXXXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

releases="$work_dir/releases.json"
curl --fail --location --retry 3 --silent --show-error \
	-H 'Accept: application/vnd.github+json' \
	-H 'X-GitHub-Api-Version: 2022-11-28' \
	--output "$releases" "$api_url"
release_tag=$(awk '
	/"tag_name"[[:space:]]*:/ {
		line = $0
		sub(/.*"tag_name"[[:space:]]*:[[:space:]]*"/, "", line)
		sub(/".*/, "", line)
		tag = line
	}
	/"prerelease"[[:space:]]*:[[:space:]]*true/ && tag != "" {
		print tag
		exit
	}
' "$releases")
test -n "$release_tag" || {
	echo "no diff-pretty prerelease was found at $api_url" >&2
	exit 1
}

base_url="https://github.com/$repo/releases/download/$release_tag"
archive="$work_dir/$asset"
checksum="$work_dir/$asset.sha256"
echo "Downloading $base_url/$asset"
curl --fail --location --retry 3 --silent --show-error \
	--output "$archive" "$base_url/$asset"
if curl --fail --location --retry 3 --silent --show-error \
	--output "$checksum" "$base_url/$asset.sha256"; then
	expected=$(awk 'NF { print $1; exit }' "$checksum")
	actual=$(sha256 "$archive")
	test "$expected" = "$actual" || {
		echo "SHA-256 mismatch for $asset" >&2
		exit 1
	}
else
	echo "No checksum asset for $asset; continuing with the verified HTTPS download" >&2
fi

mkdir -p "$work_dir/unpack"
tar -xzf "$archive" -C "$work_dir/unpack"
manifest="$work_dir/unpack/manifest"
test -f "$manifest"
test "$(awk -F= '$1 == "format" { print $2; exit }' "$manifest")" = diff-pretty-ffi-v1
test "$(awk -F= '$1 == "target" { print $2; exit }' "$manifest")" = "$target"
test -s "$work_dir/unpack/include/diff_pretty.h"
test -s "$work_dir/unpack/lib/libdiff_pretty_ffi.a"

mkdir -p "$cache_root"
rm -rf "$cache_dir"
mv "$work_dir/unpack" "$cache_dir"
echo "Cached diff-pretty FFI package at $cache_dir"
