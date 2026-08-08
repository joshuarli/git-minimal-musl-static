# git-minimal-musl-static

Builds a small, production-optimized Git distribution for Linux/aarch64 and
native macOS. The Linux build is static and uses Alpine's LLVM 22 toolchain;
the macOS build uses Apple's system Clang and system libraries. Both keep Git's
built-in commands and native transports such as SSH, but omit HTTPS/cURL,
Expat, gettext, Perl, Python, Tcl/Tk, Gitweb, and Rust.
The Linux build also omits iconv; native macOS iconv remains enabled because
Git's Darwin filename normalization requires it.

The Linux Docker build fetches and unpacks the Git source archive with
BuildKit's `ADD` instruction and a pinned SHA-256; it needs no downloader, CA
bundle, or runtime image.

```sh
make git
make macos
```

`make git` writes `dist/git` plus `git-shell` and the three server helper
symlinks. `make macos` writes the corresponding files under `dist/macos/`.
The three built-in server helpers are relative symlinks to `git`; `git-shell`
is a separate executable. Install the files together in one `bin` directory.

Run `./scripts/download-git-source.sh` to download, verify, and trim the same
pinned Git source archive into the checked-in `src/` subtree. The script keeps
the generated command and hook metadata needed after Documentation is removed.
After that, `make macos` builds without Docker, Homebrew, or a separate
compiler toolchain.

The Dockerfile runs `test/runtime.sh` in a clean Alpine stage before exporting
the artifacts. The harness checks static linking, runtime-prefix relocation,
configuration, repository operations, maintenance commands, helper layout,
and omitted features.

`git-lfs` and `git-filter-repo` are separate projects rather than Git build
features, so they are intentionally absent. `git-cvsserver` is omitted by the
`NO_PERL` build.
