# frozen_string_literal: true

# Formats a Product::Diff into a Telegram Markdown message.
class MessageFormatService
  # Maximum number of individual products to list before summarising with a count.
  IMAGE_COUNT_LIMIT = 10
  PRODUCT_COUNT_LIMIT = 20

  # @param watch_name [String] watch identifier used as the message heading
  # @param diff [Hash] diff hash with :new_products, :removed_products, :changes keys
  # @param page [Integer, nil] current page number (1-based); omit for single-page messages
  # @param total_pages [Integer, nil] total number of pages; omit for single-page messages
  def initialize(watch_name, diff, page: nil, total_pages: nil)
    @watch_name = watch_name
    @diff = diff
    @page = page
    @total_pages = total_pages
  end

  # @return [Hash] with :text (String or nil) and :photo_urls (Array<String>)
  def call
    { text: build_text, photo_urls: new_product_photo_urls + changed_product_photo_urls }
  end

  private

  # @return [String, nil]
  def build_text
    sections = [
      format_new_products(@diff[:new_products]),
      format_changes(@diff[:changes]),
      format_removed_products(@diff[:removed_products])
    ].compact
    return nil if sections.empty?

    ["*[#{@watch_name}]* changes detected#{pagination_suffix}", *sections].join("\n\n")
  end

  # @return [String]
  def pagination_suffix
    return '' if @total_pages.nil? || @total_pages <= 1

    " (#{@page}/#{@total_pages})"
  end

  # Returns image URLs for new products (used for sendMediaGroup album).
  #
  # @return [Array<String>]
  def new_product_photo_urls
    products = @diff[:new_products]
    return [] if products.nil? || products.empty?

    products[0..(IMAGE_COUNT_LIMIT - 1)].filter_map { |p| p['image'] }
  end

  # Returns image URLs for changed products (one per unique product).
  #
  # @return [Array<String>]
  def changed_product_photo_urls
    changes = @diff[:changes]
    return [] if changes.nil? || changes.empty?

    unique_products = changes.group_by(&:handle).values.map(&:first)

    unique_products[0..(IMAGE_COUNT_LIMIT - 1)].filter_map(&:image)
  end

  # @param products [Array<Hash>]
  # @return [String, nil]
  def format_new_products(products)
    return nil if products.nil? || products.empty?
    return "*New products:* #{products.size} products added" if products.size > PRODUCT_COUNT_LIMIT

    lines = products.each_with_index.map { |p, i| format_new_product(p, i + 1) }
    "*New products:*\n#{lines.join("\n")}"
  end

  # @param product [Hash]
  # @param number [Integer]
  # @return [String]
  def format_new_product(product, number)
    badge = availability_badge(product['available'])
    line = "#{number}. [#{product['title']}](#{product['url']}) : #{product['price']}"
    badge ? "#{line} #{badge}" : line
  end

  # @param changes [Array<Product::DiffService::ProductChange>]
  # @return [String, nil]
  def format_changes(changes)
    return nil if changes.nil? || changes.empty?

    lines = changes.group_by(&:handle).each_with_index.map do |(_, product_changes), i|
      format_change_entry(product_changes, i)
    end
    "*Changes:*\n#{lines.join("\n")}"
  end

  # @param product_changes [Array<Product::DiffService::ProductChange>]
  # @param index [Integer]
  # @return [String]
  def format_change_entry(product_changes, index)
    first = product_changes.first
    badge = availability_badge(first.current_available)
    prefix = "#{index + 1}. [#{first.title}](#{first.url})"
    header = badge ? "#{prefix} #{badge}:" : "#{prefix}:"
    field_lines = product_changes.map { |c| "  - #{c.field}: `#{c.previous_value}` → `#{c.current_value}`" }
    "#{header}\n#{field_lines.join("\n")}"
  end

  # @param products [Array<Hash>]
  # @return [String, nil]
  def format_removed_products(products)
    return nil if products.nil? || products.empty?

    return "*Removed products:* #{products.size} products removed" if products.size > PRODUCT_COUNT_LIMIT

    lines = products.each_with_index.map do |p, i|
      badge = availability_badge(p['available'])
      line = "#{i + 1}. [#{p['title']}](#{p['url']}) : #{p['price']}"
      badge ? "#{line} #{badge}" : line
    end
    "*Removed products:*\n#{lines.join("\n")}"
  end

  # @param available [Boolean]
  # @return [String]
  def availability_badge(available)
    return nil if available.nil?

    available ? '✅' : '❌'
  end
end
