from __future__ import annotations

from tests.conftest import REPO_ROOT


def test_dockerfile_consumes_shared_aio_base_overlay() -> None:
    dockerfile = (REPO_ROOT / "Dockerfile").read_text()

    assert "FROM dub19/aio-base:s6-3.2.1.0@" in dockerfile  # nosec B101
    assert "COPY --from=aio-base /aio-overlay/ /" in dockerfile  # nosec B101
    assert "aio-harden pre" in dockerfile  # nosec B101
    assert "aio-harden post" in dockerfile  # nosec B101
    assert "apt-get install" not in dockerfile  # nosec B101
    assert "s6-overlay/releases/download" not in dockerfile  # nosec B101
