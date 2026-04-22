# frozen_string_literal: true

require_relative 'change_detector'

# Formats a ChangeDetector diff into a Telegram Markdown message.
class MessageFormatter
  # @param watch_name [String]
  # @param diff [Hash] output of ChangeDetector.detect
  # @return [Hash] { text: String or nil, photos: Array<Hash> }
  #   Each photo hash has :image_url and :caption keys.
  def self.format(watch_name, diff)
    photos = new_product_photos(watch_name, diff[:new_products])
    text = build_text(watch_name, diff, photos)
    { text: text, photos: photos }
  end

  def self.build_text(watch_name, diff, photos)
    sections = [
      format_new_products_text(diff[:new_products], photos),
      format_changes(diff[:changes]),
      format_removed_products(diff[:removed_products])
    ].compact
    return nil if sections.empty?

    ["*[#{watch_name}]* changes detected", *sections].join("\n\n")
  end

  DETAIL_LIMIT = 10

  # Returns photo entries for new products that have images.
  def self.new_product_photos(watch_name, products)
    return [] if products.nil? || products.empty? || products.size > DETAIL_LIMIT

    products.filter_map do |p|
      next unless p['image']

      caption = "*[#{watch_name}]* New product\n[#{p['title']}](#{p['url']}) — #{p['price']}"
      { image_url: p['image'], caption: caption }
    end
  end

  # Text fallback for new products without images, or when over DETAIL_LIMIT.
  def self.format_new_products_text(products, photos)
    return nil if products.nil? || products.empty?
    return "*New products:* #{products.size} products added" if products.size > DETAIL_LIMIT

    text_products = products_without_photos(products, photos)
    return nil if text_products.empty?

    lines = text_products.map { |p| "- [#{p['title']}](#{p['url']}) — #{p['price']}" }
    "*New products:*\n#{lines.join("\n")}"
  end

  def self.products_without_photos(products, photos)
    photo_urls = photos.map { |ph| ph[:image_url] }
    products.reject { |p| photo_urls.include?(p['image']) }
  end

  def self.format_changes(changes)
    return nil if changes.nil? || changes.empty?

    lines = changes.map { |c| format_change(c) }
    "*Changes:*\n#{lines.join("\n")}"
  end

  def self.format_change(change)
    "- #{change.handle}: #{change.field} `#{change.previous_value}` → `#{change.current_value}`"
  end

  def self.format_removed_products(products)
    return nil if products.nil? || products.empty?

    return "*Removed products:* #{products.size} products removed" if products.size > DETAIL_LIMIT

    lines = products.map { |p| "- #{p['handle']}" }
    "*Removed products:*\n#{lines.join("\n")}"
  end

  private_class_method :new_product_photos, :build_text, :format_new_products_text,
                       :products_without_photos,
                       :format_changes, :format_change, :format_removed_products
end
