from __future__ import annotations

import os
import shutil
import subprocess  # nosec B404 - tests shell out to the bundled cont-init script
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONT_INIT = ROOT / "rootfs/etc/cont-init.d/01-crw-config.sh"
BASH = shutil.which("bash")
if BASH is None:
    raise RuntimeError("bash is required for cont-init tests")


def _run_cont_init(
    *,
    config_src: Path | None,
    runtime_config: Path,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    cmd_env = dict(os.environ)
    cmd_env["AIO_CRW_RUNTIME_CONFIG"] = str(runtime_config)
    if config_src is not None:
        cmd_env["AIO_CRW_CONFIG_SRC"] = str(config_src)
    if env:
        cmd_env.update(env)
    return subprocess.run(  # nosec B603 - trusted local script
        [BASH, str(CONT_INIT)],
        env=cmd_env,
        text=True,
        capture_output=True,
    )


def test_cont_init_rewrites_lightpanda_endpoint_to_localhost() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "config.docker.toml"
        src.write_text(
            '[renderer.lightpanda]\nws_url = "ws://lightpanda:9222/"\n'
            '[search]\nsearxng_url = "http://searxng:8080"\n'
        )
        out = Path(tmp) / "crw-runtime.toml"

        result = _run_cont_init(config_src=src, runtime_config=out)
        assert result.returncode == 0, result.stderr  # nosec B101
        text = out.read_text()
        assert 'ws_url = "ws://127.0.0.1:9222/"' in text  # nosec B101
        assert "ws://lightpanda:9222/" not in text  # nosec B101
        # Non-renderer keys are preserved.
        assert 'searxng_url = "http://searxng:8080"' in text  # nosec B101


def test_cont_init_writes_minimal_config_when_source_missing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "crw-runtime.toml"
        result = _run_cont_init(config_src=None, runtime_config=out)
        assert result.returncode == 0, result.stderr  # nosec B101
        assert 'ws_url = "ws://127.0.0.1:9222/"' in out.read_text()  # nosec B101


def test_cont_init_rejects_invalid_port() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "crw-runtime.toml"
        result = _run_cont_init(
            config_src=None,
            runtime_config=out,
            env={"CRW_SERVER__PORT": "not-a-port"},
        )
        assert result.returncode != 0  # nosec B101
        assert "not a valid port" in result.stderr  # nosec B101


def test_cont_init_rejects_invalid_renderer_mode() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "crw-runtime.toml"
        result = _run_cont_init(
            config_src=None,
            runtime_config=out,
            env={"CRW_RENDERER__MODE": "bogus"},
        )
        assert result.returncode != 0  # nosec B101
        assert "not a valid renderer mode" in result.stderr  # nosec B101


def test_cont_init_rejects_non_http_searxng_url() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "crw-runtime.toml"
        result = _run_cont_init(
            config_src=None,
            runtime_config=out,
            env={"CRW_SEARCH__SEARXNG_URL": "ftp://searxng:8080"},
        )
        assert result.returncode != 0  # nosec B101
        assert "must be an http(s) URL" in result.stderr  # nosec B101
