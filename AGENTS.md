# git-minimal-musl-static

Builds a small, production-optimized Git distribution for Linux/aarch64,
Linux/amd64, and native macOS. The Linux build is static and uses Alpine's
LLVM 22 toolchain;
the macOS build uses Apple's system Clang and system libraries. Both keep Git's
built-in commands and native transports such as SSH, but omit HTTPS/cURL,
Expat, gettext, Perl, Python, Tcl/Tk, and Gitweb. Upstream Git's Cargo
integration remains disabled; both builds link a target-specific downloaded
`diff-pretty` Rust static library through a small C ABI.
The Linux build also omits iconv; native macOS iconv remains enabled because
Git's Darwin filename normalization requires it.

The Linux Docker build fetches and unpacks the Git source archive with
BuildKit's `ADD` instruction and a pinned SHA-256; it needs no downloader, CA
bundle, or runtime image.

```sh
make git
make macos
make macos-local
```

`make git` and `make macos` automatically download and verify the matching
static FFI package from the newest `diff-pretty` GitHub prerelease; they do not
require Rust or Cargo.
`make macos-local` is the local-development exception: it builds the release
FFI package from `../diff-pretty` with Cargo and uses that library for the
native macOS build. Set `DIFF_PRETTY_LOCAL_ROOT` to use a different checkout.
The package is cached under `.cache/diff-pretty/ffi/`. `make git` selects
`aarch64-unknown-linux-musl` on arm64 hosts and `x86_64-unknown-linux-musl` on
x86_64 hosts, and selects the corresponding Docker platform. The macOS target
is selected from the host architecture. `DIFF_PRETTY_FFI_ROOT` remains
available as an escape hatch for an offline or locally staged package.

The native pager is opt-in: set `GIT_PAGER=builtin:diff-pretty` or
`core.pager=builtin:diff-pretty` for an interactive `git diff`, `git log`,
or `git show <commit>`. Redirected output stays on Git's ordinary byte path.
Log and show keep commit metadata in the same ordered stream as Git's semantic
file and hunk events. The FFI package is downloaded from the latest
`joshuarli/diff-pretty` release and cached under `.cache/diff-pretty/ffi/`.

`make git` writes `dist/git` plus `git-shell` and the three server helper
symlinks. `make macos` writes the corresponding files under `dist/macos/`.
The three built-in server helpers are relative symlinks to `git`; `git-shell`
is a separate executable. Install the files together in one `bin` directory.

Run `./scripts/download-git-source.sh` to download, verify, and trim the same
pinned Git source archive into the checked-in `src/` subtree. The script keeps
the generated command and hook metadata needed after Documentation is removed.
After that, `make macos` builds without Docker, Homebrew, or Rust; it requires
only Apple's native C toolchain and the downloaded static FFI package.

The Dockerfile runs `test/runtime.sh` in a clean Alpine stage before exporting
the artifacts. The harness checks static linking, runtime-prefix relocation,
configuration, repository operations, maintenance commands, helper layout,
and omitted features.

The manual GitHub Actions release workflow in `.github/workflows/release.yml`
publishes prerelease tarballs for native `macos-26`, Linux arm64, and Linux
amd64. The Linux jobs call `make git` with the checked-in Dockerfile and its
static musl toolchain; the macOS job calls `make macos`. Each release also
publishes a SHA-256 sidecar for its tarball.

`git-lfs` and `git-filter-repo` are separate projects rather than Git build
features, so they are intentionally absent. `git-cvsserver` is omitted by the
`NO_PERL` build.
