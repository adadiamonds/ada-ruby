# frozen_string_literal: true

require "minitest/autorun"
require "webrick"
require "adadiamonds"

# A local server that records the last request and answers with a canned body.
class FakeApi
  attr_reader :last, :base_url
  attr_accessor :status, :response, :headers

  def initialize
    @status = 200
    @response = {}
    @headers = {}
    @last = nil
    @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL),
                                      AccessLog: [])
    @server.mount_proc("/") do |req, res|
      @last = { method: req.request_method, path: req.unparsed_uri.split("?", 2).first, query: req.query_string.to_s,
                headers: req.header.transform_values(&:first),
                body: req.body && !req.body.empty? ? JSON.parse(req.body) : nil }
      res.status = @status
      res["Content-Type"] = "application/json"
      res["RateLimit-Limit"] = "120"
      res["RateLimit-Remaining"] = "119"
      res["RateLimit-Reset"] = "58"
      res["RateLimit-Policy"] = "120;w=60"
      @headers.each { |k, v| res[k] = v }
      res.body = @response.is_a?(String) ? @response : JSON.generate(@response)
    end
    @thread = Thread.new { @server.start }
    @base_url = "http://127.0.0.1:#{@server.config[:Port]}"
  end

  def stop
    @server.shutdown
    @thread.join
  end
end

class ClientTest < Minitest::Test
  def setup
    @api = FakeApi.new
    @client = AdaDiamonds::Client.new(base_url: @api.base_url)
  end

  def teardown
    @api.stop
  end

  def test_diamonds_builds_the_request
    @api.response = { "object" => "list", "currency" => "USD",
                      "data" => [{ "id" => "AD-1", "carat" => 1.5, "price" => 4000 }],
                      "pagination" => { "total" => 1, "limit" => 20, "offset" => 0, "has_more" => false } }
    page = @client.diamonds(shape: "Oval", min_carat: 1, max_price: 4000, sort: nil, q: "")

    assert_equal "GET", @api.last[:method]
    assert_equal "/api/v1/diamonds", @api.last[:path]
    assert_equal "max_price=4000&min_carat=1&shape=Oval", @api.last[:query]
    assert_equal "application/json", @api.last[:headers]["accept"]
    assert_match %r{\Aada-diamonds-ruby/#{AdaDiamonds::VERSION} }, @api.last[:headers]["user-agent"]
    assert_nil @api.last[:headers]["authorization"]

    assert_equal "USD", page.currency
    assert_equal 1, page.total
    assert_equal 1, page.count
    assert_equal "AD-1", page.first["id"]
    refute page.has_more?

    assert_equal 120, @client.last_rate_limit.limit
    assert_equal 119, @client.last_rate_limit.remaining
    assert_equal 58, @client.last_rate_limit.reset
    assert_equal "120;w=60", @client.last_rate_limit.policy
  end

  def test_array_params_repeat_the_key
    @client.diamonds(color: %w[D E], shape: "Round")
    assert_equal "color=D&color=E&shape=Round", @api.last[:query]
  end

  def test_object_endpoints_escape_the_identifier
    @api.response = { "id" => "a b/c" }
    assert_equal "a b/c", @client.diamond("a b/c")["id"]
    assert_equal "/api/v1/diamonds/a%20b%2Fc", @api.last[:path]

    @client.engagement_ring("oval-solitaire")
    assert_equal "/api/v1/engagement-rings/oval-solitaire", @api.last[:path]
    @client.jewelry_item("tennis-bracelet")
    assert_equal "/api/v1/jewelry/tennis-bracelet", @api.last[:path]
    @client.article("lab-diamond-guide")
    assert_equal "/api/v1/knowledge-base/lab-diamond-guide", @api.last[:path]
    @client.showrooms
    assert_equal "/api/v1/showrooms", @api.last[:path]
  end

  def test_knowledge_base_merges_the_query
    @client.knowledge_base("clarity", limit: 5)
    assert_equal "/api/v1/knowledge-base", @api.last[:path]
    assert_equal "limit=5&q=clarity", @api.last[:query]
  end

  def test_ask_hits_the_site_root
    @client.ask("oval ring under $6,000", limit: 3)
    assert_equal "/ask", @api.last[:path]
    assert_equal "limit=3&query=oval+ring+under+%246%2C000", @api.last[:query]
  end

  def test_authenticated_post_with_idempotency_key
    client = AdaDiamonds::Client.new(base_url: @api.base_url, api_key: "ada_test_123")
    @api.response = { "id" => "consult_1", "status" => "received" }
    out = client.request_consultation({ "email" => "test@example.com", "topic" => "engagement_ring" },
                                      idempotency_key: "consult-42")

    assert_equal "POST", @api.last[:method]
    assert_equal "/api/v1/consultations", @api.last[:path]
    assert_equal "Bearer ada_test_123", @api.last[:headers]["authorization"]
    assert_equal "consult-42", @api.last[:headers]["idempotency-key"]
    assert_equal "application/json", @api.last[:headers]["content-type"]
    assert_equal({ "email" => "test@example.com", "topic" => "engagement_ring" }, @api.last[:body])
    assert_equal "received", out["status"]
  end

  def test_create_key_and_batch_bodies
    @client.create_key("my-agent")
    assert_equal "/api/v1/keys", @api.last[:path]
    assert_equal({ "name" => "my-agent", "env" => "sandbox" }, @api.last[:body])

    @client.batch([{ id: "a", method: "GET", path: "/diamonds", query: { limit: 1 } }])
    assert_equal "/api/v1/batch", @api.last[:path]
    assert_equal "a", @api.last[:body]["requests"][0]["id"]
  end

  def test_api_error_carries_the_error_body
    @api.status = 429
    @api.response = { "error" => "rate_limited", "error_description" => "Slow down",
                      "documentation_url" => "https://www.adadiamonds.com/developers/api#rate-limits",
                      "retry_after_seconds" => 12 }
    err = assert_raises(AdaDiamonds::Error) { @client.diamonds }

    assert_equal 429, err.status
    assert_equal "rate_limited", err.code
    assert_equal "Slow down", err.description
    assert_equal 12, err.retry_after
    assert_match "rate-limits", err.documentation_url
    assert_equal "429 rate_limited: Slow down", err.message
  end

  def test_non_json_error_falls_back_to_http_code
    @api.status = 502
    @api.response = "<html>bad gateway</html>"
    @api.headers = { "Retry-After" => "7" }
    err = assert_raises(AdaDiamonds::Error) { @client.showrooms }

    assert_equal "http_502", err.code
    assert_equal "<html>bad gateway</html>", err.description
    assert_equal 7, err.retry_after
  end

  def test_generic_get_resolves_api_and_root_paths
    @client.get("/api/acp/checkout_sessions", {})
    assert_equal "/api/acp/checkout_sessions", @api.last[:path]
    @client.get("jewelry", category: "wedding-bands")
    assert_equal "/api/v1/jewelry", @api.last[:path]
    assert_equal "category=wedding-bands", @api.last[:query]
    @client.get("/openapi.json")
    assert_equal "/openapi.json", @api.last[:path]
  end

  def test_empty_body_returns_nil
    @api.status = 204
    @api.response = ""
    assert_nil @client.post("/jobs/1/cancel", nil)
  end
end
