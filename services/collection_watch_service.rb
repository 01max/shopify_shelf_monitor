# frozen_string_literal: true

require_relative 'showroom_client'
require_relative 'change_detector'
require_relative 'message_formatter'
require_relative 'telegram/chat_service'

# Orchestrates the monitoring flow for a +type: collection+ watch.
# Fetches the collection and its products, detects changes (new/removed products,
# price and availability changes), and sends Telegram notifications.
class CollectionWatchService
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
    diff = ChangeDetector.detect(current_products, @previous_products)
    notify!(diff)

    { watch_name: @watch_name, type: 'collection', status: 'ok',
      products: current_products, products_count: current_products.size }
  end

  private

  def fetch_products(collection)
    @client.collection_products(collection).map { |p| snapshot_product(p) }
  end

  def snapshot_product(product)
    {
      'handle' => product.handle,
      'title' => product.title,
      'price' => product.price,
      'available' => product.available?,
      'url' => product.url,
      'variants' => product.variants.map do |v|
        { 'title' => v.title, 'price' => v.price, 'available' => v.available? }
      end
    }
  end

  def notify!(diff)
    message = MessageFormatter.format(@watch_name, diff)
    return if message.nil? && !force_notify?

    message ||= "ShelfMonitor [#{@watch_name}]: no changes detected (force notify)"
    Telegram::ChatService.new(**chat_params).deliver(message)
    @logger.info("#{@watch_name}: notification sent")
  end

  def force_notify?
    ENV['FORCE_NOTIFY'] == 'true'
  end

  def chat_params
    return {} unless @params.key?('telegram_chat_id')

    { chat_id: @params['telegram_chat_id'] }
  end
end
