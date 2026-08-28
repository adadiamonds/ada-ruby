# adadiamonds

Official Ruby client for the [Ada Diamonds](https://www.adadiamonds.com) API: live lab grown diamond inventory, engagement ring settings, fine jewelry, showrooms, and the diamond buying guides.

Standard library only (`net/http`, `json`). Ruby 2.6 or newer.

- Documentation: https://www.adadiamonds.com/developers
- REST reference: https://www.adadiamonds.com/developers/api
- OpenAPI 3.1: https://www.adadiamonds.com/openapi.json
- MCP server (for tool use instead of HTTP): https://www.adadiamonds.com/mcp

## Install

```bash
gem install adadiamonds
```

or in a Gemfile:

```ruby
gem "adadiamonds"
```

Reading the catalog needs no account and no API key (120 requests per minute). An API key raises that to 600 and unlocks the write endpoints. Every price is in US dollars.

## Examples

### Search live diamond inventory

```ruby
require "adadiamonds"

client = AdaDiamonds::Client.new # anonymous
page = client.diamonds(shape: "Oval", min_carat: 1, max_price: 4000, sort: "price_asc")
page.each do |stone|
  puts [stone["carat"], stone["shape"], stone["price"]].join(" ")
end
p client.last_rate_limit # #<struct limit=120, remaining=119, reset=58, policy="...">
```

### Quote a complete ring

An engagement ring is a setting plus a loose diamond, priced separately. Setting prices never include the center stone.

```ruby
setting = client.engagement_rings(shape: "Oval", type: "Solitaire", limit: 1).first
stone = client.diamonds(shape: "Oval", min_carat: 1.5, max_carat: 1.6, sort: "price_asc", limit: 1).first
puts setting["priceFrom"] + stone["price"] # US dollars
```

### Authenticate and write

```ruby
key = AdaDiamonds::Client.new.create_key("my-agent", env: "sandbox")
client = AdaDiamonds::Client.new(api_key: key["api_key"]) # 600 requests/min

begin
  client.request_consultation(
    { "email" => "test@example.com", "topic" => "engagement_ring" },
    idempotency_key: "consult-42" # a retry cannot create two requests
  )
rescue AdaDiamonds::Error => e
  puts [e.status, e.code, e.description, e.retry_after].inspect
end
```

Sandbox keys (`ada_test_*`) return well-formed responses and contact nobody.

### Ask a question (NLWeb)

```ruby
answer = client.ask("oval lab diamond engagement ring under $6,000")
```

### Anything else

Every method maps to one endpoint under `/api/v1`. For endpoints without a helper, `get` and `post` take a path relative to `/api/v1` (or absolute on the site) and return the decoded JSON:

```ruby
bands = client.get("/jewelry", category: "wedding-bands")
```

## Methods

| Method | Endpoint |
| --- | --- |
| `diamonds`, `diamond` | `GET /api/v1/diamonds`, `GET /api/v1/diamonds/{id}` |
| `engagement_rings`, `engagement_ring` | `GET /api/v1/engagement-rings`, `.../{slug}` |
| `jewelry`, `jewelry_item` | `GET /api/v1/jewelry`, `.../{slug}` |
| `knowledge_base`, `article` | `GET /api/v1/knowledge-base`, `.../{slug}` |
| `showrooms` | `GET /api/v1/showrooms` |
| `request_consultation` | `POST /api/v1/consultations` |
| `create_key` | `POST /api/v1/keys` |
| `batch` | `POST /api/v1/batch` (up to 20 GETs in one round trip) |
| `ask` | `GET /ask` (NLWeb) |

List methods return an `AdaDiamonds::Page` (`data`, `pagination`, `total`, `has_more?`, and `Enumerable`). Errors are `AdaDiamonds::Error` with `status`, `code`, `description`, `documentation_url`, and `retry_after`. Every response's `RateLimit-*` headers are available from `last_rate_limit`; pace yourself rather than retrying into a 429.

## Etiquette

Identify your agent with `AdaDiamonds::Client.new(user_agent: "my-agent/1.0 (+https://example.com)")`. Bulk scraping of the HTML catalog is not permitted; this API and `POST /api/v1/exports` are the supported way to read it. Diamond inventory changes continuously; re-check a stone before quoting it.

## Development

```bash
bundle install
bundle exec rake test
```

## License

MIT. Copyright Ada Diamonds, Inc.
