#!/command/with-contenv bash
# shellcheck shell=bash
set -euo pipefail

# =============================================================================
# crw-config: validate environment and materialize the crw-server runtime config
#
# crw-server loads config.default.toml, then the file named by $CRW_CONFIG, then
# applies CRW_* env overrides on top (env always wins). The bundled
# config.docker.toml is already AIO-tailored: it points LightPanda at the
# in-container instance (ws://127.0.0.1:9222/) and leaves SearXNG unset so the
# operator supplies it via CRW_SEARCH__SEARXNG_URL. The rewrite below is a
# defensive fallback for the case where an operator mounts a docker-compose
# config that still targets the compose hostname `lightpanda`; in that single
# case we rewrite it to the in-container instance. A failed validation aborts
# startup (s6 stage2 fails fast).
#
# Internal path overrides (AIO_* prefix, never read by crw-server) let the
# non-integration tests exercise this script without a container.
# =============================================================================

# --- Validate environment ---------------------------------------------------
# CRW_SERVER__PORT must be a valid TCP port when set.
if [[ -n ${CRW_SERVER__PORT-} ]]; then
	if ! [[ ${CRW_SERVER__PORT} =~ ^[0-9]+$ ]] || ((CRW_SERVER__PORT < 1 || CRW_SERVER__PORT > 65535)); then
		echo "[crw-config] ERROR: CRW_SERVER__PORT='${CRW_SERVER__PORT}' is not a valid port (1-65535)." >&2
		exit 1
	fi
fi

# CRW_RENDERER__MODE must be a known renderer mode when set.
if [[ -n ${CRW_RENDERER__MODE-} ]]; then
	case "${CRW_RENDERER__MODE}" in
	auto | lightpanda | playwright | chrome | camoufox | none) ;;
	*)
		echo "[crw-config] ERROR: CRW_RENDERER__MODE='${CRW_RENDERER__MODE}' is not a valid renderer mode (auto|lightpanda|playwright|chrome|camoufox|none)." >&2
		exit 1
		;;
	esac
fi

# CRW_SEARCH__SEARXNG_URL must be an http(s) URL when set.
if [[ -n ${CRW_SEARCH__SEARXNG_URL-} ]]; then
	case "${CRW_SEARCH__SEARXNG_URL}" in
	http://* | https://*) ;;
	*)
		echo "[crw-config] ERROR: CRW_SEARCH__SEARXNG_URL='${CRW_SEARCH__SEARXNG_URL}' must be an http(s) URL." >&2
		exit 1
		;;
	esac
fi

# --- Write runtime config ---------------------------------------------------
CONFIG_SRC="${AIO_CRW_CONFIG_SRC:-/app/config.docker.toml}"
RUNTIME_CONFIG="${AIO_CRW_RUNTIME_CONFIG:-/config/aio/crw-runtime.toml}"
mkdir -p "$(dirname "${RUNTIME_CONFIG}")"

if [[ -f ${CONFIG_SRC} ]]; then
	cp "${CONFIG_SRC}" "${RUNTIME_CONFIG}"
	# Point the bundled LightPanda endpoint at the in-container instance.
	# config.docker.toml targets the docker-compose hostname `lightpanda`;
	# in this single-container AIO LightPanda runs on 127.0.0.1:9222.
	sed -i 's#ws://lightpanda:9222/#ws://127.0.0.1:9222/#g' "${RUNTIME_CONFIG}"
else
	# No bundled docker config; write a minimal runtime config.
	cat >"${RUNTIME_CONFIG}" <<'EOF'
[renderer.lightpanda]
ws_url = "ws://127.0.0.1:9222/"
EOF
fi

chown root:appuser /config/aio "${RUNTIME_CONFIG}" 2>/dev/null || true
chmod 750 "$(dirname "${RUNTIME_CONFIG}")"
chmod 640 "${RUNTIME_CONFIG}"

echo "[crw-config] Runtime config written to ${RUNTIME_CONFIG}."
