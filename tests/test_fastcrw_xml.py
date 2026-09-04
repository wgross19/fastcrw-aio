from __future__ import annotations

from defusedxml import ElementTree as ET

from tests.conftest import REPO_ROOT

XML = REPO_ROOT / "fastcrw-aio.xml"


def _config_map() -> dict[str, dict[str, str]]:
    root = ET.parse(XML).getroot()
    assert root is not None  # nosec B101
    return {c.attrib["Name"]: c.attrib for c in root.findall("Config")}


def test_xml_is_well_formed() -> None:
    root = ET.parse(XML).getroot()
    assert root is not None  # nosec B101
    assert root.tag == "Container"  # nosec B101


def test_xml_exposes_api_port_default() -> None:
    cfg = _config_map()
    api = cfg["API Port"]
    assert api["Target"] == "CRW_SERVER__PORT"  # nosec B101
    assert api["Default"] == "3000"  # nosec B101
    assert api["Display"] == "always"  # nosec B101


def test_xml_publishes_container_port_3000() -> None:
    root = ET.parse(XML).getroot()
    assert root is not None  # nosec B101
    publish = root.find("./Networking/Publish/Port")
    assert publish is not None  # nosec B101
    container_port = publish.find("ContainerPort")
    host_port = publish.find("HostPort")
    assert container_port is not None and container_port.text == "3000"  # nosec B101
    assert host_port is not None and host_port.text == "3000"  # nosec B101
    webui = root.find("WebUI")
    assert webui is not None and webui.text is not None  # nosec B101
    assert "[PORT:3000]" in webui.text  # nosec B101


def test_xml_exposes_searxng_url_and_renderer_toggle() -> None:
    cfg = _config_map()
    assert cfg["SearXNG URL"]["Target"] == "CRW_SEARCH__SEARXNG_URL"  # nosec B101
    renderer = cfg["Renderer Mode"]
    assert renderer["Target"] == "CRW_RENDERER__MODE"  # nosec B101
    assert renderer["Default"] == "auto"  # nosec B101


def test_xml_exposes_memory_limit() -> None:
    cfg = _config_map()
    mem = cfg["Memory Limit"]
    assert mem["Target"] == "CRW_MEM_LIMIT"  # nosec B101
    assert mem["Default"] == "2g"  # nosec B101


def test_xml_advanced_toggles_are_hidden_and_keyed_to_env() -> None:
    cfg = _config_map()
    expected = {
        "OpenAlex API Key": "CRW_SEARCH__OPENALEX_API_KEY",
        "OpenAlex Mailto": "CRW_SEARCH__OPENALEX_MAILTO",
        "Semantic Scholar API Key": "CRW_SEARCH__S2_API_KEY",
        "API Keys": "CRW_AUTH__API_KEYS",
    }
    for name, target in expected.items():
        field = cfg[name]
        assert field["Target"] == target  # nosec B101
        assert field["Display"] == "advanced"  # nosec B101


def test_xml_does_not_expose_list_type_engine_env_vars() -> None:
    # crw-server parses list-type settings (TOML sequences) from config files
    # only; a CRW_* env var always arrives as a string and fails config load,
    # which crash-loops the server on boot. Engine lists must stay on the
    # bundled config defaults (research_engines / github_engines).
    cfg = _config_map()
    for forbidden in ("CRW_SEARCH__RESEARCH_ENGINES", "CRW_SEARCH__GITHUB_ENGINES"):
        assert all(c["Target"] != forbidden for c in cfg.values())  # nosec B101


def test_xml_optional_heavy_chrome_renderer_noted() -> None:
    # Chrome is an opt-in tier; it is not the default renderer and requires an
    # external CDP endpoint (Chrome is not bundled in the single-container AIO).
    cfg = _config_map()
    desc = cfg["Renderer Mode"]["Description"].lower()
    assert "chrome" in desc  # nosec B101
    assert cfg["Renderer Mode"]["Default"] != "chrome"  # nosec B101
