DOCKER_BUILD ?= docker buildx build
DOCKER_BUILD_CACHE_ARGS ?=

GIT_VERSION ?= 2.55.0
GIT_SOURCE_DIR ?= src/git-$(GIT_VERSION)
HOST_ARCH := $(shell uname -m)
ifeq ($(filter arm64 aarch64,$(HOST_ARCH)),)
DIFF_PRETTY_LINUX_TARGET ?= x86_64-unknown-linux-musl
else
DIFF_PRETTY_LINUX_TARGET ?= aarch64-unknown-linux-musl
endif
ifeq ($(DIFF_PRETTY_LINUX_TARGET),aarch64-unknown-linux-musl)
DOCKER_PLATFORM ?= linux/arm64
else ifeq ($(DIFF_PRETTY_LINUX_TARGET),x86_64-unknown-linux-musl)
DOCKER_PLATFORM ?= linux/amd64
else
$(error unsupported DIFF_PRETTY_LINUX_TARGET: $(DIFF_PRETTY_LINUX_TARGET) (use aarch64-unknown-linux-musl or x86_64-unknown-linux-musl))
endif
ifeq ($(shell uname -m),x86_64)
DIFF_PRETTY_MAC_TARGET ?= x86_64-apple-darwin
else
DIFF_PRETTY_MAC_TARGET ?= aarch64-apple-darwin
endif
DIFF_PRETTY_FFI_ROOT ?= $(CURDIR)/.cache/diff-pretty/ffi

MACOS_DIST ?= dist/macos
MACOS_CFLAGS ?= -O3 -flto -DNDEBUG -pipe -ffunction-sections -fdata-sections
MACOS_LDFLAGS ?= -flto -Wl,-dead_strip

.PHONY: git macos

git:
	@set -eu; \
		sh scripts/download-diff-pretty-ffi.sh "$(DIFF_PRETTY_LINUX_TARGET)" "$(abspath $(DIFF_PRETTY_FFI_ROOT))"; \
		ffi_root="$(abspath $(DIFF_PRETTY_FFI_ROOT)/$(DIFF_PRETTY_LINUX_TARGET))"; \
		ffi_include="$$ffi_root/include"; \
		ffi_lib="$$ffi_root/lib/libdiff_pretty_ffi.a"; \
		test -f "$$ffi_include/diff_pretty.h" || { echo "missing prebuilt diff-pretty header: $$ffi_include/diff_pretty.h" >&2; exit 1; }; \
		test -f "$$ffi_lib" || { echo "missing prebuilt diff-pretty static library: $$ffi_lib" >&2; exit 1; }; \
		mkdir -p dist; \
		rm -f dist/git dist/git-shell dist/git-upload-archive dist/git-upload-pack dist/git-receive-pack; \
		$(DOCKER_BUILD) $(DOCKER_BUILD_CACHE_ARGS) \
			--build-context diff-pretty="$$ffi_root" \
			--build-context diff-pretty-lib="$$ffi_root/lib" \
			--platform=$(DOCKER_PLATFORM) \
			--progress=plain \
			--target=artifacts \
			--output=type=local,dest=dist \
			.; \
		test -s dist/git; \
		for helper in git-upload-archive git-shell git-upload-pack git-receive-pack; do \
			test -x "dist/$$helper"; \
		done; \
		test ! -e dist/git-cvsserver; \
		test ! -e dist/git-lfs; \
		test ! -e dist/git-filter-repo; \
		echo "Wrote dist/git and dist/git-*"

macos:
	@set -eu; \
		sh scripts/download-diff-pretty-ffi.sh "$(DIFF_PRETTY_MAC_TARGET)" "$(abspath $(DIFF_PRETTY_FFI_ROOT))"; \
		ffi_root="$(abspath $(DIFF_PRETTY_FFI_ROOT)/$(DIFF_PRETTY_MAC_TARGET))"; \
		ffi_include="$$ffi_root/include"; \
		ffi_lib="$$ffi_root/lib/libdiff_pretty_ffi.a"; \
		test -f "$$ffi_include/diff_pretty.h" || { echo "missing prebuilt diff-pretty header: $$ffi_include/diff_pretty.h" >&2; exit 1; }; \
		test -f "$$ffi_lib" || { echo "missing prebuilt diff-pretty static library: $$ffi_lib" >&2; exit 1; }; \
		test "$$(uname -s)" = Darwin; \
		test -f "$(GIT_SOURCE_DIR)/Makefile" || { \
			echo "run ./scripts/download-git-source.sh first" >&2; \
			exit 1; \
		}; \
		sdkroot="$$(xcrun --sdk macosx --show-sdk-path)"; \
		cc="$$(xcrun --sdk macosx --find clang)"; \
		ar="$$(xcrun --sdk macosx --find ar)"; \
		ranlib="$$(xcrun --sdk macosx --find ranlib)"; \
		strip="$$(xcrun --sdk macosx --find strip)"; \
		jobs="$$(sysctl -n hw.ncpu)"; \
		$(MAKE) -C "$(GIT_SOURCE_DIR)" -j"$$jobs" \
			CC="$$cc" \
			AR="$$ar" \
			RANLIB="$$ranlib" \
			STRIP="$$strip" \
			CPPFLAGS="-isysroot $$sdkroot -DDIFF_PRETTY_ENABLED -I$$ffi_include" \
			CFLAGS="$(MACOS_CFLAGS)" \
			LDFLAGS="$(MACOS_LDFLAGS) -isysroot $$sdkroot" \
			NO_CURL=YesPlease \
			NO_DARWIN_PORTS=YesPlease \
			NO_EXPAT=YesPlease \
			NO_GETTEXT=YesPlease \
			NO_GITWEB=YesPlease \
			NO_HOMEBREW=YesPlease \
			NO_OPENSSL=YesPlease \
			NO_PERL=YesPlease \
			NO_PYTHON=YesPlease \
			NO_REGEX=NeedsStartEnd \
			NO_RUST=YesPlease \
			DIFF_PRETTY_FFI_LIB="$$ffi_lib" \
			DIFF_PRETTY_FFI_INCLUDE="$$ffi_include" \
			NO_TCLTK=YesPlease \
			RUNTIME_PREFIX=YesPlease \
			prefix=/usr \
			bindir=/usr/bin \
			gitexecdir=bin \
			git \
			git-upload-archive \
			git-shell \
			git-upload-pack \
			git-receive-pack; \
		"$$cc" --version | sed -n '1p'; \
		"$(GIT_SOURCE_DIR)/git" --version; \
		"$$strip" -S -x "$(GIT_SOURCE_DIR)/git" "$(GIT_SOURCE_DIR)/git-shell"; \
		rm -rf "$(MACOS_DIST)"; \
		mkdir -p "$(MACOS_DIST)"; \
		cp -a "$(GIT_SOURCE_DIR)/git" "$(GIT_SOURCE_DIR)/git-shell" "$(MACOS_DIST)/"; \
		for helper in git-upload-archive git-upload-pack git-receive-pack; do \
			test -x "$(GIT_SOURCE_DIR)/$$helper"; \
			ln -s git "$(MACOS_DIST)/$$helper"; \
		done; \
			test -x "$(MACOS_DIST)/git"; \
			test -x "$(MACOS_DIST)/git-shell"; \
		expected_exec_path="$$("$(MACOS_DIST)/git" --exec-path)"; \
		GIT_BIN_DIR="$(abspath $(MACOS_DIST))" \
		GIT_EXPECTED_EXEC_PATH="$$expected_exec_path" \
			sh test/runtime.sh; \
		echo "Wrote $(MACOS_DIST)/git and $(MACOS_DIST)/git-*"
