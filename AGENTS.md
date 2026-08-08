# git-minimal-musl-static

Builds a small, production-optimized Git distribution for Linux/aarch64 and
native macOS. The Linux build is static and uses Alpine's LLVM 22 toolchain;
the macOS build uses Apple's system Clang and system libraries. Both keep Git's
built-in commands and native transports such as SSH, but omit HTTPS/cURL,
Expat, gettext, Perl, Python, Tcl/Tk, and Gitweb. Upstream Git's Cargo
integration remains disabled; both builds link the adjacent `diff-pretty`
Rust static library through a small C ABI.
The Linux build also omits iconv; native macOS iconv remains enabled because
Git's Darwin filename normalization requires it.

The Linux Docker build fetches and unpacks the Git source archive with
BuildKit's `ADD` instruction and a pinned SHA-256; it needs no downloader, CA
bundle, or runtime image.

```sh
make git
make macos
```

The native pager is opt-in: set `GIT_PAGER=builtin:diff-pretty` or
`core.pager=builtin:diff-pretty` for an interactive `git diff`. Redirected
output stays on Git's ordinary byte path. `DIFF_PRETTY_DIR` defaults to
`../diff-pretty` and can point at another checkout.

`make git` writes `dist/git` plus `git-shell` and the three server helper
symlinks. `make macos` writes the corresponding files under `dist/macos/`.
The three built-in server helpers are relative symlinks to `git`; `git-shell`
is a separate executable. Install the files together in one `bin` directory.

Run `./scripts/download-git-source.sh` to download, verify, and trim the same
pinned Git source archive into the checked-in `src/` subtree. The script keeps
the generated command and hook metadata needed after Documentation is removed.
After that, `make macos` builds without Docker or Homebrew; it does require the
Rust toolchain used by the adjacent `diff-pretty` checkout to produce its
static library.

The Dockerfile runs `test/runtime.sh` in a clean Alpine stage before exporting
the artifacts. The harness checks static linking, runtime-prefix relocation,
configuration, repository operations, maintenance commands, helper layout,
and omitted features.

`git-lfs` and `git-filter-repo` are separate projects rather than Git build
features, so they are intentionally absent. `git-cvsserver` is omitted by the
`NO_PERL` build.
