# frozen_string_literal: true

require_relative 'change_detector'

# Formats a ChangeDetector diff into a Telegram Markdown message.
class MessageFormatter
  DETAIL_LIMIT = 10

  def initialize(watch_name, diff)
    @watch_name = watch_name
    @diff = diff
  end

  def call
    { text: build_text, photo_urls: new_product_photo_urls }
  end

  private

  def build_text
    sections = [
      format_new_products(@diff[:new_products]),
      format_changes(@diff[:changes]),
      format_removed_products(@diff[:removed_products])
    ].compact
    return nil if sections.empty?

    ["*[#{@watch_name}]* changes detected", *sections].join("\n\n")
  end

  # Returns image URLs for new products (used for sendMediaGroup album).
  def new_product_photo_urls
    products = @diff[:new_products]
    return [] if products.nil? || products.empty? || products.size > DETAIL_LIMIT

    products.filter_map { |p| p['image'] }
  end

  def format_new_products(products)
    return nil if products.nil? || products.empty?
    return "*New products:* #{products.size} products added" if products.size > DETAIL_LIMIT

    lines = products.each_with_index.map { |p, i| format_new_product(p, i + 1) }
    "*New products:*\n#{lines.join("\n")}"
  end

  def format_new_product(product, number)
    "#{number}. [#{product['title']}](#{product['url']}) — #{product['price']}"
  end

  def format_changes(changes)
    return nil if changes.nil? || changes.empty?

    lines = changes.map { |c| format_change(c) }
    "*Changes:*\n#{lines.join("\n")}"
  end

  def format_change(change)
    "- #{change.handle}: #{change.field} `#{change.previous_value}` → `#{change.current_value}`"
  end

  def format_removed_products(products)
    return nil if products.nil? || products.empty?

    return "*Removed products:* #{products.size} products removed" if products.size > DETAIL_LIMIT

    lines = products.map { |p| "- #{p['handle']}" }
    "*Removed products:*\n#{lines.join("\n")}"
  end
end
