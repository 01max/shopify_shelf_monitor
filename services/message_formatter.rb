# frozen_string_literal: true

require_relative 'change_detector'

# Formats a ChangeDetector diff into a Telegram Markdown message.
class MessageFormatter
  # @param watch_name [String]
  # @param diff [Hash] output of ChangeDetector.detect
  # @return [String, nil] Markdown-formatted message, or nil if diff is empty
  def self.format(watch_name, diff)
    sections = [
      format_new_products(diff[:new_products]),
      format_changes(diff[:changes]),
      format_removed_products(diff[:removed_products])
    ].compact

    return nil if sections.empty?

    ["*ShelfMonitor [#{watch_name}]*: changes detected!", *sections].join("\n\n")
  end

  DETAIL_LIMIT = 10

  def self.format_new_products(products)
    return nil if products.nil? || products.empty?

    if products.size > DETAIL_LIMIT
      return "*New products:* #{products.size} products added"
    end

    lines = products.map { |p| format_new_product(p) }
    "*New products:*\n#{lines.join("\n")}"
  end

  def self.format_new_product(product)
    "- [#{product['title']}](#{product['url']}) — #{product['price']}"
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

    if products.size > DETAIL_LIMIT
      return "*Removed products:* #{products.size} products removed"
    end

    lines = products.map { |p| "- #{p['handle']}" }
    "*Removed products:*\n#{lines.join("\n")}"
  end

  private_class_method :format_new_products, :format_new_product,
                       :format_changes, :format_change, :format_removed_products
end
