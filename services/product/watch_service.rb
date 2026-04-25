# frozen_string_literal: true

require_relative '../showroom_client'
require_relative 'diff_service'
require_relative '../message_format_service'
require_relative '../notifier'

# Orchestrates the monitoring flow for a +type: products+ watch.
# Fetches each product by handle, detects changes, and sends Telegram notifications.
module Product
  # Product::WatchService
  class WatchService
    # @param watch_name [String]
    # @param params [Hash] watch config from config.yml
    # @param logger [Logger]
    # @param previous_products [Array<Hash>, nil] product snapshots from previous report
    def initialize(watch_name, params, logger, previous_products = nil)
      @watch_name = watch_name
      @params = params
      @logger = logger
      @previous_products = previous_products || []
      @client = ShowroomClient.new(store: params['store'], logger: logger,
                                   rate_limit_ms: params.fetch('rate_limit_ms', ShowroomClient::DEFAULT_RATE_LIMIT_MS))
    end

    # @return [Hash] result with :watch_name, :type, :status, :products
    def call
      current_products = fetch_products
      diff = Product::DiffService.new(current_products, @previous_products).call
      notify!(diff)

      { watch_name: @watch_name, type: 'products', status: 'ok', products: current_products }
    end

    private

    # @return [Array<Hash>]
    def fetch_products
      @params.fetch('handles', []).filter_map do |handle|
        product = @client.find_product(handle)
        snapshot_product(product)
      rescue Showroom::NotFound
        @logger.warn("#{@watch_name}: product '#{handle}' not found, skipping")
        nil
      end
    end

    # @param product [Showroom::Product]
    # @return [Hash]
    def snapshot_product(product)
      snapshot_base(product).tap do |s|
        image = product.main_image
        s['image'] = image.src if image
      end
    end

    # @param product [Showroom::Product]
    # @return [Hash]
    def snapshot_base(product)
      { 'handle' => product.handle, 'title' => product.title,
        'price' => product.price, 'available' => product.available?,
        'url' => product.url,
        'variants' => product.variants.map { |v| snapshot_variant(v) } }
    end

    # @param variant [Showroom::Variant]
    # @return [Hash]
    def snapshot_variant(variant)
      { 'title' => variant.title, 'price' => variant.price, 'available' => variant.available? }
    end

    # @param diff [Hash]
    # @return [void]
    def notify!(diff)
      result = MessageFormatService.new(@watch_name, diff).call
      return if result[:text].nil? && result[:photo_urls].empty? && !force_notify?

      send_notifications(result)
      @logger.info("#{@watch_name}: notification sent")
    end

    # @param result [Hash] formatted message result from MessageFormatService
    # @return [void]
    def send_notifications(result)
      telegram = Notifier.build(**chat_params)
      telegram.send_media_group(result[:photo_urls]) if result[:photo_urls].any?
      text = result[:text]
      text ||= "[#{@watch_name}] no changes detected (force notify)" if force_notify? && result[:photo_urls].empty?
      telegram.deliver(text) if text
    end

    # @return [Boolean]
    def force_notify?
      ENV['FORCE_NOTIFY'] == 'true'
    end

    # @return [Hash]
    def chat_params
      return {} unless @params.key?('telegram_chat_id')

      { chat_id: @params['telegram_chat_id'] }
    end
  end
end
