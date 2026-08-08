# syntax=docker/dockerfile:1.18@sha256:dabfc0969b935b2080555ace70ee69a5261af8a8f1b4df97b9e7fbcf6722eddf

# alpine:latest currently resolves to Alpine 3.24.1. Keep the resolved digest
# here so the base image is still the requested latest line without moving the
# build when the tag moves.
FROM alpine:latest@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS build

ARG LLVM_VERSION=22.1.3

# Alpine's Clang driver still uses GCC's musl crtbegin/libgcc files for a
# static link; clang remains the compiler selected below.
RUN apk add --no-cache \
        clang22=22.1.3-r2 \
        gcc=15.2.0-r5 \
        lld22=22.1.3-r0 \
        llvm22=22.1.3-r0 \
        linux-headers=7.0.0-r1 \
        make=4.4.1-r4 \
        zlib-dev=1.3.2-r0 \
        zlib-static=1.3.2-r0

ENV PATH=/usr/lib/llvm22/bin:$PATH \
    CC=clang \
    AR=llvm22-ar \
    RANLIB=llvm22-ranlib \
    LD=ld.lld \
    STRIP=llvm22-strip

RUN test "$(apk --print-arch)" = aarch64 \
    && clang --version | grep -q "${LLVM_VERSION}" \
    && ld.lld --version | grep -q "${LLVM_VERSION}"

WORKDIR /src

# BuildKit fetches and unpacks the official release archive. Its SHA-256 keeps
# the source immutable without putting a downloader or CA bundle in the image.
ADD --checksum=sha256:457fdb04dc8728e007d4688695e6912e6f680727920f2a40bf11eacc17505357 \
    --unpack=true \
    https://www.kernel.org/pub/software/scm/git/git-2.55.0.tar.xz /src/

WORKDIR /src/git-2.55.0

# musl does not expose REG_STARTEND; use Git's compatibility regex.
RUN set -eux; \
    make -j"$(getconf _NPROCESSORS_ONLN)" \
        CC="$CC" \
        AR="$AR" \
        RANLIB="$RANLIB" \
        LD="$LD" \
        STRIP="$STRIP" \
        CFLAGS="-O3 -flto -DNDEBUG -pipe -ffunction-sections -fdata-sections" \
        LDFLAGS="-static -flto -fuse-ld=lld -Wl,--gc-sections" \
        NO_CURL=YesPlease \
        NO_EXPAT=YesPlease \
        NO_GETTEXT=YesPlease \
        NO_GITWEB=YesPlease \
        NO_ICONV=YesPlease \
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
    ./git --version; \
    llvm22-strip --strip-unneeded git git-shell; \
    mkdir /out; \
    test -x git; \
    test -x git-shell; \
    cp -a git git-shell /out/; \
    for helper in git-upload-archive git-upload-pack git-receive-pack; do \
        test -x "$helper"; \
        ln -s git "/out/$helper"; \
    done; \
    for helper in git git-shell; do \
        test -z "$(ldd "$helper" 2>&1 | grep -F '=>' || true)"; \
    done

FROM alpine:latest@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS runtime-test

COPY --from=build /out/ /usr/local/bin/
COPY --chmod=755 test/runtime.sh /usr/local/bin/git-minimal-runtime-test

RUN /usr/local/bin/git-minimal-runtime-test \
    && rm /usr/local/bin/git-minimal-runtime-test

FROM scratch AS artifacts

COPY --from=runtime-test /usr/local/bin/ /
