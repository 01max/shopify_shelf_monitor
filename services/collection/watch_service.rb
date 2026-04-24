# frozen_string_literal: true

require_relative '../showroom_client'
require_relative '../product/diff_service'
require_relative '../message_format_service'
require_relative '../telegram/chat_service'

# Orchestrates the monitoring flow for a +type: collection+ watch.
# Fetches the collection and its products, detects changes (new/removed products,
# price and availability changes), and sends Telegram notifications.
module Collection
  # Collection::WatchService
  class WatchService
    SEND_BATCH_SIZE = 20

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

    # @return [Hash] result with :watch_name, :type, :status, :products, :products_count
    def call
      collection = @client.find_collection(@params['handle'])
      current_products = fetch_products(collection)
      diff = Product::DiffService.new(current_products, @previous_products).call
      notify!(diff)

      { watch_name: @watch_name, type: 'collection', status: 'ok',
        products: current_products, products_count: current_products.size }
    end

    private

    # @param collection [Showroom::Collection]
    # @return [Array<Hash>]
    def fetch_products(collection)
      @client.collection_products(collection).map { |p| snapshot_product(p) }
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
      batches = build_batches(diff)
      return force_notify_empty! if batches.empty? && force_notify?

      batches.each { |batch| send_batch(batch) }
      @logger.info("#{@watch_name}: notification sent") if batches.any?
    end

    # @param diff [Hash]
    # @return [void]
    def send_batch(batch)
      result = MessageFormatService.new(@watch_name, batch).call
      send_notifications(result) unless result[:text].nil? && result[:photo_urls].empty?
    end

    # @return [void]
    def force_notify_empty!
      send_notifications({ text: nil, photo_urls: [] })
      @logger.info("#{@watch_name}: notification sent")
    end

    # Splits a diff into chunks of at most SEND_BATCH_SIZE products across all three categories.
    #
    # @param diff [Hash]
    # @return [Array<Hash>]
    def build_batches(diff) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
      new_p   = diff[:new_products] || []
      removed = diff[:removed_products] || []
      changes = diff[:changes] || []
      return [] if new_p.empty? && removed.empty? && changes.empty?

      [].tap do |batches|
        new_p.each_slice(SEND_BATCH_SIZE)   { |s| batches << { new_products: s,  removed_products: [], changes: [] } }
        removed.each_slice(SEND_BATCH_SIZE) { |s| batches << { new_products: [], removed_products: s, changes: [] } }
        changes.map(&:handle).uniq.each_slice(SEND_BATCH_SIZE) do |handles|
          batches << { new_products: [], removed_products: [],
                       changes: changes.select { |c| handles.include?(c.handle) } }
        end
      end
    end

    # @param result [Hash] formatted message result from MessageFormatService
    # @return [void]
    def send_notifications(result)
      telegram = Telegram::ChatService.new(**chat_params)
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
