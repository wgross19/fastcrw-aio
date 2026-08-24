from __future__ import annotations

import os
import shutil
import subprocess  # nosec B404 - tests shell out to the bundled cont-init script
import tempfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONT_INIT = ROOT / "rootfs/etc/cont-init.d/01-crw-config.sh"
BUNDLED_CONFIG = ROOT / "config.docker.toml"
BASH = shutil.which("bash")
if BASH is None:
    raise RuntimeError("bash is required for cont-init tests")


def _load_bundled_config() -> dict:
    with BUNDLED_CONFIG.open("rb") as fh:
        return tomllib.load(fh)


def test_bundled_config_is_valid_toml() -> None:
    cfg = _load_bundled_config()
    assert "server" in cfg  # nosec B101
    assert "renderer" in cfg  # nosec B101
    assert "search" in cfg  # nosec B101


def test_bundled_config_points_lightpanda_at_in_container_instance() -> None:
    cfg = _load_bundled_config()
    lp = cfg["renderer"].get("lightpanda", {})
    assert lp.get("ws_url") == "ws://127.0.0.1:9222/"  # nosec B101
    # The compose hostname must not appear in the AIO bundle.
    assert "ws://lightpanda:9222/" not in BUNDLED_CONFIG.read_text()  # nosec B101


def test_bundled_config_leaves_searxng_unset_for_env() -> None:
    # No bundled SearXNG sidecar in the single-container AIO; the operator
    # supplies the URL via CRW_SEARCH__SEARXNG_URL (env wins over the TOML).
    cfg = _load_bundled_config()
    assert cfg["search"].get("searxng_url") is None  # nosec B101
    assert "searxng_url" not in cfg["search"]  # nosec B101


def test_cont_init_on_bundled_config_preserves_aiotuned_defaults() -> None:
    # Running cont-init against the bundled config must be a stable no-op for
    # the AIO-tailored values (lightpanda already points at 127.0.0.1:9222 and
    # SearXNG stays unset), while still materializing the runtime config.
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "crw-runtime.toml"
        result = subprocess.run(  # nosec B603 - trusted local script
            [BASH, str(CONT_INIT)],
            env={
                **os.environ,
                "AIO_CRW_CONFIG_SRC": str(BUNDLED_CONFIG),
                "AIO_CRW_RUNTIME_CONFIG": str(out),
            },
            text=True,
            capture_output=True,
        )
        assert result.returncode == 0, result.stderr  # nosec B101
        with out.open("rb") as fh:
            runtime = tomllib.load(fh)
        assert (
            runtime["renderer"]["lightpanda"]["ws_url"] == "ws://127.0.0.1:9222/"
        )  # nosec B101
        # SearXNG stays unset (no bundled sidecar; operator sets the env var).
        assert "searxng_url" not in runtime["search"]  # nosec B101
        # The bundled tuning keys are preserved through the materialization.
        assert runtime["request"]["deadline_ms_default"] == 15000  # nosec B101
        assert runtime["server"]["rate_limit_rps"] == 0  # nosec B101
