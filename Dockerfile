# syntax=docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
# checkov:skip=CKV_DOCKER_3: s6-overlay requires root init so cont-init scripts can prepare state before services drop privileges
# checkov:skip=CKV_DOCKER_8: s6-overlay entrypoint must start as root so init scripts can prepare filesystem state before dropping privileges

FROM wgross19/aio-base:s6-3.2.1.0@sha256:07db479a01a95ba28480b4605f5d1cc8bedb574b77cf167ee46e29b9558fee90 AS aio-base

# Replace this starter runtime with the real upstream image once the derived repo is wired.
FROM python:3.14-slim-bookworm@sha256:2e256d0381371566ed96980584957ed31297f437569b79b0e5f7e17f2720e53a

# hadolint ignore=DL3002
USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --from=aio-base /aio-overlay/ /

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

EXPOSE 8080

ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=300000
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health', timeout=5).read()" || exit 1

ENTRYPOINT ["/init"]
