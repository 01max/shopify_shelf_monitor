# frozen_string_literal: true

require_relative 'change_detector'

# Formats a ChangeDetector diff into a Telegram Markdown message.
class MessageFormatter
  # @param watch_name [String]
  # @param diff [Hash] output of ChangeDetector.detect
  # @return [Hash] { text: String or nil, photo_urls: Array<String> }
  def self.format(watch_name, diff)
    photo_urls = new_product_photo_urls(diff[:new_products])
    text = build_text(watch_name, diff)
    { text: text, photo_urls: photo_urls }
  end

  def self.build_text(watch_name, diff)
    sections = [
      format_new_products(diff[:new_products]),
      format_changes(diff[:changes]),
      format_removed_products(diff[:removed_products])
    ].compact
    return nil if sections.empty?

    ["*[#{watch_name}]* changes detected", *sections].join("\n\n")
  end

  DETAIL_LIMIT = 10

  # Returns image URLs for new products (used for sendMediaGroup album).
  def self.new_product_photo_urls(products)
    return [] if products.nil? || products.empty? || products.size > DETAIL_LIMIT

    products.filter_map { |p| p['image'] }
  end

  def self.format_new_products(products)
    return nil if products.nil? || products.empty?
    return "*New products:* #{products.size} products added" if products.size > DETAIL_LIMIT

    lines = products.each_with_index.map { |p, i| format_new_product(p, i + 1) }
    "*New products:*\n#{lines.join("\n")}"
  end

  def self.format_new_product(product, number)
    "#{number}. [#{product['title']}](#{product['url']}) — #{product['price']}"
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

  private_class_method :new_product_photo_urls, :build_text,
                       :format_new_products, :format_new_product,
                       :format_changes, :format_change, :format_removed_products
end
