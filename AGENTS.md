# AGENTS.md

This repository is an official Ada Diamonds SDK. The canonical agent-facing
resources for Ada Diamonds (https://www.adadiamonds.com) are:

- Agent tools repo (plugin manifest, skills, MCP configs): https://github.com/adadiamonds/agent-tools
- Agent guide: https://www.adadiamonds.com/agents.md
- llms.txt: https://www.adadiamonds.com/llms.txt
- OpenAPI 3.1: https://www.adadiamonds.com/openapi.json
- MCP servers: https://www.adadiamonds.com/mcp (product) and https://www.adadiamonds.com/mcp/docs (docs), Streamable HTTP, no credential for the catalog
- Developer docs: https://www.adadiamonds.com/developers (markdown via `Accept: text/markdown`)

Rules for changes in this repo:

- Never invent endpoints, parameters, scopes, or prices; verify against the live OpenAPI description.
- Prices are US dollars as decimals, never cents.
- An engagement ring is a setting plus a loose diamond, priced separately.
- Keep the client surface aligned with https://www.adadiamonds.com/openapi.json; if the spec and this code disagree, the spec wins.
