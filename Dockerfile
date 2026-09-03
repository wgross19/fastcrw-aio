# syntax=docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
# checkov:skip=CKV_DOCKER_3: s6-overlay requires root init so cont-init scripts can prepare state before services drop privileges
# checkov:skip=CKV_DOCKER_8: s6-overlay entrypoint must start as root so init scripts can prepare filesystem state before dropping privileges

# =============================================================================
# fastcrw-aio
#
# Builds crw-server v0.33.0 (us/crw @ bcf64392) with an upstream Rust
# cargo-chef multi-stage build, then overlays the shared aio-base s6 runtime,
# bundles the LightPanda JS renderer, curl (with its shared-lib closure) and a
# healthcheck. Exposes crw-server on 3000; LightPanda runs in-container on
# 9222 (not published) as the default JS renderer.
# =============================================================================

# Which workspace crate to build + cook. Deliberately narrowed to crw-server
# (with the cdp feature) so we do not compile crw-cli / crw-mcp. MUST be
# identical in the cacher (cook) and builder (final compile) stages so the
# cooked artifacts fingerprint-match.
ARG CARGO_PACKAGES="-p crw-server --features cdp"

# ---- shared aio-base overlay (s6 + lifecycle tooling) -----------------------
# Not pulled into the Rust stages; used as the runtime s6 overlay provider.
FROM dub19/aio-base:s6-3.2.1.0@sha256:203e643ac3360e7c0930aa007fcaa0780d69cb068b5ce1bfe55bf1dfa4f36126 AS aio-base

# ---- upstream crw build (us/crw v0.33.0 @ bcf64392) -------------------------
FROM rust:1.97-bookworm@sha256:606f3248aa86ce49e0b98d9e0bbffde042adeb18982320f97bcc218615de1c99 AS chef
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Pinned upstream release tag, monitored by aio-fleet (github-tags, us/crw).
# The tarball sha256 below must move together with this tag; the monitor uses
# `notify` strategy for exactly this reason (it cannot recompute the checksum).
ARG CRW_VERSION=v0.33.0

# Rust target for the requested build arch. Only native (amd64) is wired here:
# arm64 cross-compilation would need a pre-provisioned cross toolchain because
# this image deliberately has no apt-get (aio policy). LightPanda is amd64-only
# upstream, so the AIO bundle targets linux/amd64.
ARG TARGETARCH
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) RUST_TARGET=x86_64-unknown-linux-gnu ;; \
      arm64) \
        if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then \
          echo "ERROR: arm64 cross-build requires a preinstalled aarch64-linux-gnu-gcc toolchain; this image cannot provision one (aio policy). Build with --platform=linux/amd64 instead." >&2; \
          exit 1; \
        fi; \
        RUST_TARGET=aarch64-unknown-linux-gnu ;; \
      *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
    esac; \
    rustup target add "$RUST_TARGET"; \
    echo "$RUST_TARGET" > /rust_target

# Pinned cargo-chef so the cacher layer is deterministic. Parses the edition
# 2024 / resolver-2 workspace used by crw v0.33.0.
RUN cargo install cargo-chef --locked --version 0.1.77

ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
    CARGO_PROFILE_RELEASE_LTO=thin \
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16

# Fetch + verify the pinned upstream source once (shared by the build stages).
# The tarball sha256 is the pin for us/crw v0.33.0 (bcf64392); the sha must be
# updated in lockstep with CRW_VERSION above.
RUN set -eux; \
    curl -fsSL -o /tmp/crw.tar.gz \
      "https://github.com/us/crw/archive/refs/tags/${CRW_VERSION}.tar.gz"; \
    echo "d80781259b184175a0ed8db8df061ef5a7a063aebfa3fe94ffe4e62127e7c78c  /tmp/crw.tar.gz" | sha256sum -c -; \
    mkdir -p /app; \
    tar -C /app -xzf /tmp/crw.tar.gz --strip-components=1; \
    rm -f /tmp/crw.tar.gz

WORKDIR /app

# ---- planner: derive the dependency recipe from the manifests only ----------
FROM chef AS planner
RUN cargo chef prepare --recipe-path /recipe.json

# ---- cacher: compile ONLY the dependency graph (durable cache layer) --------
FROM chef AS cacher
ARG CARGO_PACKAGES
COPY --from=planner /recipe.json /recipe.json
# $CARGO_PACKAGES is intentionally unquoted so it word-splits into cargo args.
RUN set -eux; \
    RUST_TARGET="$(cat /rust_target)"; \
    cargo chef cook --release --target "$RUST_TARGET" \
      $CARGO_PACKAGES \
      --recipe-path /recipe.json

# ---- builder: compile crw-server on top of the cooked deps -------------------
FROM cacher AS builder
ARG CARGO_PACKAGES
# cargo-chef cook replaces workspace sources with dependency-only stubs.
# Restore the real source tree before compiling the application binary.
COPY --from=chef /app/ /app/
RUN set -eux; \
    RUST_TARGET="$(cat /rust_target)"; \
    cargo build --release --target "$RUST_TARGET" \
      $CARGO_PACKAGES; \
    mkdir -p /out; \
    cp "target/${RUST_TARGET}/release/crw-server" /out/crw-server; \
    test -f /out/crw-server

# ---- curl provider: collect /usr/bin/curl + its shared-lib closure ----------
# The runtime is an apt-free debian slim, so curl is copied from the build
# image. We copy the binary plus the transitive .so closure and recreate the
# SONAME symlinks so the dynamic loader can resolve them at runtime.
FROM rust:1.97-bookworm@sha256:606f3248aa86ce49e0b98d9e0bbffde042adeb18982320f97bcc218615de1c99 AS curl-bundle
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -eu; \
    mkdir -p /out/usr/bin /out/usr/lib/x86_64-linux-gnu; \
    cp /usr/bin/curl /out/usr/bin/curl; \
    ldd /usr/bin/curl | grep -oE '/[^ ]+\.so[^ ]*' | sort -u | while read -r lib; do \
      real="$(readlink -f "$lib")"; \
      cp "$real" "/out/usr/lib/x86_64-linux-gnu/$(basename "$real")"; \
      if [ "$(basename "$real")" != "$(basename "$lib")" ]; then \
        ln -sf "$(basename "$real")" "/out/usr/lib/x86_64-linux-gnu/$(basename "$lib")"; \
      fi; \
    done

# ---- LightPanda renderer bundle ---------------------------------------------
# Upstream publishes a single amd64 binary; the runtime copies just the binary.
FROM lightpanda/browser@sha256:43152c5077a932ee6a9b5b0e440ce7df9b9adfd3121cc31c74fb4a27289a981c AS lightpanda

# ---- runtime ----------------------------------------------------------------
FROM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818

# hadolint ignore=DL3002
USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# s6-overlay + aio lifecycle scripts (must land before cont-init harden runs).
COPY --from=aio-base /aio-overlay/ /

# Bundle crw-server, its config defaults, curl (+libs), and LightPanda.
COPY --from=builder /out/crw-server /usr/local/bin/crw-server
COPY --from=builder /app/config.default.toml /app/config.default.toml
# AIO-tailored overrides layered on top of config.default.toml, matching the
# upstream /docker-compose/fastcrw tuning but adapted for the single-container
# image (lightpanda in-container on 127.0.0.1:9222, chrome opt-in, external
# SearXNG via env). This repo copy replaces the upstream compose config because
# the compose hostnames (lightpanda/chrome/searxng) do not resolve in the AIO.
COPY config.docker.toml /app/config.docker.toml
COPY --from=curl-bundle /out/usr/bin/curl /usr/bin/curl
COPY --from=curl-bundle /out/usr/lib/x86_64-linux-gnu/ /usr/lib/x86_64-linux-gnu/
COPY --from=lightpanda /usr/bin/lightpanda /usr/local/bin/lightpanda
# debian:bookworm-slim has no CA bundle. Keep HTTPS clients functional after
# aio-harden post removes only the snakeoil certificate.
COPY --from=chef /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

RUN aio-harden pre && \
    groupadd --system appuser && \
    useradd --system --gid appuser --create-home --home-dir /home/appuser --shell /usr/sbin/nologin appuser && \
    mkdir -p /config /data /run/service-app && \
    chown -R appuser:appuser /run/service-app && \
    aio-harden post

COPY rootfs/ /

RUN find /etc/cont-init.d -type f -exec chmod +x {} \; && \
    find /etc/services.d -type f -name run -exec chmod +x {} \; && \
    find /usr/local/bin -type f -name '*.py' -exec chmod +x {} \;

VOLUME ["/config", "/data"]

# crw-server resolves config.default.toml relative to the working directory.
WORKDIR /app

# crw-server API on 3000; LightPanda CDP stays internal on 9222.
EXPOSE 3000

ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=300000
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:3000/health >/dev/null || exit 1

ENTRYPOINT ["/init"]
