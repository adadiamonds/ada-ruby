# frozen_string_literal: true

module AdaDiamonds
  # Production host.
  DEFAULT_BASE_URL = "https://www.adadiamonds.com"
  # REST API version this client targets.
  API_VERSION = "v1"
  USER_AGENT = "ada-diamonds-ruby/#{VERSION} (+https://www.adadiamonds.com/developers)"

  # Site-root endpoints that do not live under /api/v1.
  ROOT_PATHS = ["/ask", "/mcp", "/openapi.json", "/llms.txt"].freeze

  # A non-2xx response, decoded from the API's JSON error body: a stable
  # machine-readable +code+, a human-readable +description+ that says what to
  # do next, and the HTTP +status+. +documentation_url+ and +retry_after+
  # (seconds) are carried when the API sends them.
  class Error < StandardError
    attr_reader :status, :code, :description, :documentation_url, :retry_after, :body

    def initialize(status:, code:, description: "", documentation_url: nil, retry_after: 0, body: {})
      @status = status
      @code = code
      @description = description
      @documentation_url = documentation_url
      @retry_after = retry_after
      @body = body
      super(description.empty? ? "#{status} #{code}" : "#{status} #{code}: #{description}")
    end
  end

  # The RateLimit-* headers from the most recent response. Counters are per
  # 60 second window; treat them as a pacing signal.
  RateLimit = Struct.new(:limit, :remaining, :reset, :policy, keyword_init: true)

  # One page of a list response: catalog items plus pagination. Items are
  # plain hashes because the catalog schema evolves faster than a client
  # release; the field names match the OpenAPI document exactly.
  class Page
    include Enumerable

    attr_reader :object, :currency, :data, :pagination

    def initialize(body)
      body ||= {}
      @object = body["object"]
      @currency = body["currency"]
      @data = body["data"] || []
      @pagination = body["pagination"] || {}
    end

    def each(&block)
      @data.each(&block)
    end

    def total
      @pagination["total"]
    end

    def limit
      @pagination["limit"]
    end

    def offset
      @pagination["offset"]
    end

    def has_more?
      @pagination["has_more"] == true
    end
  end

  # Calls the Ada Diamonds REST API. Every public method maps to exactly one
  # endpoint; anything the client does can be reproduced with curl.
  class Client
    attr_reader :base_url, :api_key, :user_agent, :timeout, :last_rate_limit, :last_headers

    # +api_key+: an ada_live_* / ada_test_* key or an OAuth access token (nil
    # means anonymous). +base_url+ points at another host (a staging
    # deployment, a proxy). +user_agent+ identifies your agent.
    def initialize(api_key: nil, base_url: DEFAULT_BASE_URL, user_agent: USER_AGENT, timeout: 30)
      @api_key = api_key
      @base_url = base_url.sub(%r{/+\z}, "")
      @user_agent = user_agent
      @timeout = timeout
      @last_rate_limit = nil
      @last_headers = {}
    end

    # ---------------------------------------------------------------- catalog

    # Searches available loose lab grown diamonds. Filters: shape, min_carat,
    # max_carat, min_price, max_price, color, clarity, cut, sort (price_asc |
    # price_desc | carat_asc | carat_desc), limit, offset.
    def diamonds(params = {})
      Page.new(get("/diamonds", params))
    end

    # Fetches one stone by id (the catalog id or grading report number).
    def diamond(id)
      get("/diamonds/#{escape(id)}")
    end

    # Searches ring settings. Filters: shape, style, type, min_price,
    # max_price, q, limit, offset. Setting prices exclude the center stone.
    def engagement_rings(params = {})
      Page.new(get("/engagement-rings", params))
    end

    # Fetches one setting by slug.
    def engagement_ring(slug)
      get("/engagement-rings/#{escape(slug)}")
    end

    # Searches wedding bands, earrings, necklaces, bracelets, and fashion
    # rings. Filters: category, type, shape, min_price, max_price, q, limit, offset.
    def jewelry(params = {})
      Page.new(get("/jewelry", params))
    end

    # Fetches one jewelry product by slug.
    def jewelry_item(slug)
      get("/jewelry/#{escape(slug)}")
    end

    # Lists the buying guides and articles. +query+ may be nil.
    def knowledge_base(query = nil, params = {})
      merged = params.dup
      merged[:q] = query if query && !query.empty?
      Page.new(get("/knowledge-base", merged))
    end

    # Fetches one article by slug, with its body as markdown.
    def article(slug)
      get("/knowledge-base/#{escape(slug)}")
    end

    # Lists showroom locations, hours, and remote consultation options.
    def showrooms
      get("/showrooms")
    end

    # ----------------------------------------------------------------- writes

    # Asks a jeweler to contact the customer. Requires the appointments:write
    # scope (any API key). Sandbox keys return a well-formed response and
    # contact nobody. Pass an +idempotency_key+ so a retried call cannot
    # create two requests.
    def request_consultation(payload, idempotency_key: nil)
      headers = idempotency_key ? { "Idempotency-Key" => idempotency_key } : {}
      request(:post, "/consultations", body: payload, headers: headers)
    end

    # Issues a self-serve API key. +env+ is "sandbox" or "production". The key
    # is returned once, in the api_key field; only a hash is stored.
    def create_key(name, env: "sandbox")
      post("/keys", { name: name, env: env })
    end

    # Runs up to 20 GET requests in one round trip via POST /api/v1/batch.
    # Each request is a hash with id, method, path, and an optional query.
    # The response carries one responses entry per request, in order, each
    # with its own id, status, and body.
    def batch(requests)
      post("/batch", { requests: requests })
    end

    # ------------------------------------------------------------------ nlweb

    # Sends a natural-language question to the NLWeb /ask endpoint and returns
    # the JSON answer (products and guides with citations).
    def ask(query, params = {})
      get("/ask", params.merge(query: query))
    end

    # ---------------------------------------------------------------- generic

    # GET any path relative to /api/v1 ("/diamonds") or absolute on the site
    # ("/ask", "/api/acp/...") and decode the JSON response.
    def get(path, params = {})
      request(:get, path, params: params)
    end

    # POST a JSON body to any path and decode the JSON response.
    def post(path, body = nil)
      request(:post, path, body: body)
    end

    # Sends one request. Returns the decoded JSON (nil for an empty body) or
    # raises AdaDiamonds::Error for a non-2xx response.
    def request(method, path, params: {}, body: nil, headers: {})
      uri = URI(resolve(path))
      query = encode_params(params)
      uri.query = [uri.query, query].compact.reject(&:empty?).join("&") unless query.empty?

      klass = method.to_s.upcase == "POST" ? Net::HTTP::Post : Net::HTTP::Get
      req = klass.new(uri)
      req["Accept"] = "application/json"
      req["User-Agent"] = user_agent
      req["Authorization"] = "Bearer #{api_key}" if api_key && !api_key.empty?
      headers.each { |k, v| req[k] = v }
      if body
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout
      res = http.request(req)

      remember(res)
      raw = res.body.to_s
      status = res.code.to_i
      raise decode_error(status, raw, res) unless (200..299).cover?(status)
      return nil if status == 204 || raw.strip.empty?

      JSON.parse(raw)
    end

    private

    def escape(value)
      URI.encode_www_form_component(value.to_s).gsub("+", "%20")
    end

    def resolve(path)
      path = path.to_s
      return path if path.start_with?("http://", "https://")

      path = "/#{path}" unless path.start_with?("/")
      bare = path.split("?", 2).first
      return "#{base_url}#{path}" if path.start_with?("/api/") || ROOT_PATHS.include?(bare)

      "#{base_url}/api/#{API_VERSION}#{path}"
    end

    # Builds a query string with deterministic key order. Nil and empty-string
    # values are skipped, so a caller can pass optional filters without pruning
    # them first. Arrays are repeated as multiple values of the same key.
    def encode_params(params)
      return "" if params.nil? || params.empty?

      pairs = []
      params.keys.map(&:to_s).sort.each do |key|
        value = params.fetch(key.to_sym) { params[key] }
        Array(value).each do |item|
          next if item.nil?

          text = item.to_s
          next if text.empty?

          pairs << [key, text]
        end
      end
      URI.encode_www_form(pairs)
    end

    def remember(res)
      @last_headers = res.each_header.to_h
      to_i = ->(name) { res[name].to_s.strip.to_i }
      @last_rate_limit = RateLimit.new(
        limit: to_i.call("RateLimit-Limit"),
        remaining: to_i.call("RateLimit-Remaining"),
        reset: to_i.call("RateLimit-Reset"),
        policy: res["RateLimit-Policy"].to_s
      )
    end

    def decode_error(status, raw, res)
      code = "http_#{status}"
      description = ""
      documentation_url = nil
      retry_after = 0
      body = {}
      parsed = begin
        raw.empty? ? nil : JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
      if parsed.is_a?(Hash)
        body = parsed
        code = parsed["error"] if parsed["error"].is_a?(String) && !parsed["error"].empty?
        description = parsed["error_description"] if parsed["error_description"].is_a?(String)
        documentation_url = parsed["documentation_url"] if parsed["documentation_url"].is_a?(String)
        retry_after = parsed["retry_after_seconds"].to_i if parsed["retry_after_seconds"].is_a?(Numeric)
      elsif !raw.empty?
        description = raw[0, 500]
      end
      retry_after = res["Retry-After"].to_s.strip.to_i if retry_after.zero? && res["Retry-After"]
      Error.new(status: status, code: code, description: description, documentation_url: documentation_url,
                retry_after: retry_after, body: body)
    end
  end
end
