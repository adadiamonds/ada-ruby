# frozen_string_literal: true

# Official Ruby client for the Ada Diamonds API: live lab grown diamond
# inventory, engagement ring settings, fine jewelry, showrooms, and the
# diamond buying guides.
#
# Reading the catalog needs no account and no API key (120 requests per
# minute). An API key or OAuth access token raises the limit to 600 and
# unlocks the write endpoints. Every price is in US dollars.
#
#   client = AdaDiamonds::Client.new
#   page = client.diamonds(shape: "Oval", min_carat: 1, max_price: 4000)
#   page.data.each { |stone| puts [stone["carat"], stone["shape"], stone["price"]].join(" ") }
#
# Documentation: https://www.adadiamonds.com/developers
# OpenAPI: https://www.adadiamonds.com/openapi.json
require "json"
require "net/http"
require "uri"

require_relative "adadiamonds/version"
require_relative "adadiamonds/client"
