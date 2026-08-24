from __future__ import annotations

import pytest

from tests.helpers import DockerRuntime, docker_available

IMAGE_TAG = "aio-template:pytest"
pytestmark = pytest.mark.integration


@pytest.fixture(scope="session")
def runtime() -> DockerRuntime:
    if not docker_available():
        pytest.skip("Docker is unavailable; integration tests require Docker/OrbStack.")

    runtime = DockerRuntime(IMAGE_TAG)
    runtime.build()
    return runtime


def test_crw_server_serves_health_and_lightpanda_cdp(runtime: DockerRuntime) -> None:
    with runtime.container() as container:
        container.wait_for_http(path="/health")

        # crw-server API responds on /health.
        health = container.exec("curl -fsS http://127.0.0.1:3000/health").stdout
        assert health  # nosec B101

        # LightPanda CDP is reachable on 9222 inside the container.
        cdp = container.exec(
            "curl -fsS http://127.0.0.1:9222/json/version"
        ).stdout
        assert "Lightpanda" in cdp  # nosec B101


def test_runtime_config_written_and_points_at_bundled_lightpanda(
    runtime: DockerRuntime,
) -> None:
    with runtime.container() as container:
        container.wait_for_http(path="/health")
        assert container.path_exists("/config/aio/crw-runtime.toml")  # nosec B101

        config = container.read_text("/config/aio/crw-runtime.toml")
        assert 'ws_url = "ws://127.0.0.1:9222/"' in config  # nosec B101
        assert "ws://lightpanda:9222/" not in config  # nosec B101
