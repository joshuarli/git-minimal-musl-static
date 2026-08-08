DOCKER_BUILD ?= docker buildx build
DOCKER_BUILD_CACHE_ARGS ?=
DOCKER_PLATFORM ?= linux/arm64

GIT_VERSION ?= 2.55.0
GIT_SOURCE_URL ?= https://www.kernel.org/pub/software/scm/git/git-$(GIT_VERSION).tar.xz
GIT_SOURCE_SHA256 ?= 457fdb04dc8728e007d4688695e6912e6f680727920f2a40bf11eacc17505357
GIT_SOURCE_DIR ?= src/git-$(GIT_VERSION)
GIT_SOURCE_ARCHIVE ?= src/git-$(GIT_VERSION).tar.xz
GIT_SOURCE_STAMP ?= $(GIT_SOURCE_DIR)/.source-ready

MACOS_DIST ?= dist/macos
MACOS_CFLAGS ?= -O3 -flto -DNDEBUG -pipe -ffunction-sections -fdata-sections
MACOS_LDFLAGS ?= -flto -Wl,-dead_strip

.PHONY: git macos source

source: $(GIT_SOURCE_STAMP)

$(GIT_SOURCE_ARCHIVE):
	@set -eu; \
		mkdir -p "$(dir $@)"; \
		command -v curl >/dev/null; \
		curl --fail --location --retry 3 --output "$@.tmp" "$(GIT_SOURCE_URL)"; \
		mv "$@.tmp" "$@"

$(GIT_SOURCE_STAMP): $(GIT_SOURCE_ARCHIVE)
	@set -eu; \
		command -v shasum >/dev/null; \
		printf '%s  %s\n' "$(GIT_SOURCE_SHA256)" "$(GIT_SOURCE_ARCHIVE)" | shasum -a 256 -c -; \
		mkdir -p "$(dir $(GIT_SOURCE_DIR))"; \
		rm -rf "$(GIT_SOURCE_DIR)"; \
		tar -xJf "$(GIT_SOURCE_ARCHIVE)" -C "$(dir $(GIT_SOURCE_DIR))"; \
		test -f "$(GIT_SOURCE_DIR)/Makefile"; \
		touch "$@"

git:
	@set -eu; \
		mkdir -p dist; \
		rm -f dist/git dist/git-shell dist/git-upload-archive dist/git-upload-pack dist/git-receive-pack; \
		$(DOCKER_BUILD) $(DOCKER_BUILD_CACHE_ARGS) \
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

macos: $(GIT_SOURCE_STAMP)
	@set -eu; \
		test "$$(uname -s)" = Darwin; \
		sdkroot="$$(xcrun --sdk macosx --show-sdk-path)"; \
		cc="$$(xcrun --sdk macosx --find clang)"; \
		ar="$$(xcrun --sdk macosx --find ar)"; \
		ranlib="$$(xcrun --sdk macosx --find ranlib)"; \
		strip="$$(xcrun --sdk macosx --find strip)"; \
		jobs="$$(sysctl -n hw.ncpu)"; \
		$(MAKE) -C "$(GIT_SOURCE_DIR)" clean; \
		$(MAKE) -C "$(GIT_SOURCE_DIR)" -j"$$jobs" \
			CC="$$cc" \
			AR="$$ar" \
			RANLIB="$$ranlib" \
			STRIP="$$strip" \
			CPPFLAGS="-isysroot $$sdkroot" \
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
		GIT_BIN_DIR="$(MACOS_DIST)" \
		GIT_EXPECTED_EXEC_PATH="$$expected_exec_path" \
			sh test/runtime.sh; \
		echo "Wrote $(MACOS_DIST)/git and $(MACOS_DIST)/git-*"
