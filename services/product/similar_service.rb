# frozen_string_literal: true

require_relative '../showroom_client'
require_relative '../notifier'
require_relative '../similar_format_service'

module Product
  # Fetches similar products for each handle in a +type: products+ watch
  # and sends a formatted digest via the configured notifier.
  class SimilarService
    # @param watch_name [String]
    # @param params [Hash] watch config from config.yml
    # @param logger [Logger]
    def initialize(watch_name, params, logger)
      @watch_name = watch_name
      @params = params
      @logger = logger
      @client = ShowroomClient.new(store: params['store'], logger: logger,
                                   rate_limit_ms: params.fetch('rate_limit_ms', ShowroomClient::DEFAULT_RATE_LIMIT_MS))
    end

    # @return [Hash] result with :watch_name, :type, :status
    def call
      entries = fetch_similar_entries
      notify!(entries)
      { watch_name: @watch_name, type: 'similar', status: 'ok' }
    end

    private

    # @return [Array<Hash>] each entry has :product (Hash) and :similar (Array<Hash>)
    def fetch_similar_entries
      @params.fetch('handles', []).filter_map do |handle|
        product = @client.find_product(handle)
        base_url = product.url.delete_suffix("/products/#{product.handle}")
        similars = product.similar.map do |s|
          { title: s.title, handle: s.handle, price: s.price, url: "#{base_url}/products/#{s.handle}" }
        end
        { product: { title: product.title, handle: product.handle, price: product.price, url: product.url },
          similar: similars }
      rescue Showroom::NotFound
        @logger.warn("#{@watch_name}: product '#{handle}' not found, skipping")
        nil
      end
    end

    # @param entries [Array<Hash>]
    # @return [void]
    def notify!(entries)
      text = SimilarFormatService.new(@watch_name, entries).call
      return if text.nil?

      Notifier.build(**chat_params).deliver(text)
      @logger.info("#{@watch_name}: similar products notification sent")
    end

    # @return [Hash]
    def chat_params
      return {} unless @params.key?('telegram_chat_id')

      { chat_id: @params['telegram_chat_id'] }
    end
  end
end
