# fastcrw-aio

[fastCRW](https://github.com/us/crw) as one Unraid container. fastCRW is a Rust-native, Firecrawl-compatible search, scrape, crawl, map, and extract backend.

`fastcrw-aio` runs one s6-supervised image:

- `crw-server` on port `3000`
- Bundled LightPanda on internal port `9222`
- External SearXNG for Search and Research
- No bundled LLM. Hermes is the summary and answer layer.

Point Hermes or any Firecrawl SDK at `http://<lan>:3000`.

## What it provides

- Scrape: `/v1/scrape` and `/v2/scrape`
- Crawl: `/v1/crawl` and `/v2/crawl`
- Map: `/v1/map` and `/v2/map`
- Extract: `/v1/extract` and `/v2/extract`
- Batch scrape: `/v1/batch/scrape` and `/v2/batch/scrape`
- Parse: `/v2/parse`
- Search: `/v1/search` and `/v2/search`
- Health: `/health`
- MCP: `/mcp` on the same API port

## Search and research

fastCRW does not bundle SearXNG.

Set `CRW_SEARCH__SEARXNG_URL` to an external SearXNG instance with its JSON API enabled.
Search and research need this setting. Scrape, crawl, map, extract, and parse work without it.

Recommended SearXNG engines:

- Web search engines
- `arxiv`
- `crossref`
- `google scholar`
- `semantic scholar`
- `github`

Optional advanced fields support OpenAlex, Semantic Scholar, research engines, GitHub engines, and an API-key gate.

## First boot

1. Install the `fastcrw-aio` Unraid template.
2. Set `CRW_SEARCH__SEARXNG_URL` for Search and Research.
3. Leave the default port and memory values unless you need custom limits.
4. Apply the template.
5. Wait for `/health`.
6. Point Hermes at `http://<lan>:3000`.

The container writes runtime configuration under `/config` and runtime data under `/data`.

## Image

- Docker Hub: [dub19/fastcrw-aio](https://hub.docker.com/r/dub19/fastcrw-aio)
- GHCR: [ghcr.io/wgross19/fastcrw-aio](https://github.com/users/wgross19/packages/container/package/fastcrw-aio)
- Upstream: `us/crw` `v0.31.0` at `fa26843a`
- Published rolling tags: `latest` and the commit SHA tag
- Platform: `linux/amd64`

## Configuration

Core fields:

- `CRW_SERVER__PORT`, default `3000`
- `CRW_SEARCH__SEARXNG_URL`, external SearXNG URL
- `CRW_RENDERER__MODE`, default `auto`
- `CRW_MEM_LIMIT`, default `2g`

Advanced fields are optional and hidden in the Unraid template.

LightPanda is the default JavaScript renderer. Chrome is not bundled. An external Chrome CDP endpoint remains optional.

## Existing Compose stack

This image does not replace `/docker-compose/fastcrw` automatically.

Keep the existing Compose stack until a separate migration decision is approved.

## License

The fastcrw-aio wrapper is MIT.

The upstream fastCRW engine and MCP server are AGPL-3.0. The repository keeps the upstream source reference and pinned version.

See `LICENSE` and the upstream `us/crw` license for the applicable terms.
