# frozen_string_literal: true

require 'showroom'

# Rate-limited wrapper around the Showroom gem.
#
# Adds a configurable sleep between API calls and retries once on 429 (Too Many Requests).
# All Shopify API access goes through this class so rate limiting lives in one place.
class ShowroomClient
  DEFAULT_RATE_LIMIT_MS = 500
  RETRY_DELAY = 2

  # @param store [String] Shopify domain, e.g. "my-store.myshopify.com"
  # @param rate_limit_ms [Integer] milliseconds to sleep between requests
  # @param logger [Logger]
  def initialize(store:, logger:, rate_limit_ms: DEFAULT_RATE_LIMIT_MS)
    @client = Showroom::Client.new(store: store)
    @rate_limit_ms = rate_limit_ms
    @logger = logger
  end

  # @param handle [String] product handle
  # @return [Showroom::Product]
  def find_product(handle)
    throttle { @client.product(handle) }
  end

  # @param handle [String] collection handle
  # @return [Showroom::Collection]
  def find_collection(handle)
    throttle { @client.collection(handle) }
  end

  # Fetches all products in a collection, paginating automatically.
  #
  # @param collection [Showroom::Collection]
  # @return [Array<Showroom::Product>]
  def collection_products(collection)
    expected = collection.products_count
    [].tap do |products|
      (1..).each do |page|
        batch = throttle { collection.products(limit: 250, page: page) }
        break if batch.empty?

        products.concat(batch)
        break if batch.size < 250 || (expected && products.size >= expected)
      end
    end
  end

  private

  # Sleeps for the configured rate limit, then yields.
  # Retries once on Showroom::TooManyRequests with a backoff.
  #
  # @yield block to execute after the rate-limit sleep
  # @return [Object] the return value of the block
  def throttle
    sleep(@rate_limit_ms / 1000.0)
    yield
  rescue Showroom::TooManyRequests
    @logger.warn("Rate limited, retrying in #{RETRY_DELAY}s...")
    sleep(RETRY_DELAY)
    yield
  end
end
