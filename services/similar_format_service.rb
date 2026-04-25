# frozen_string_literal: true

# Formats similar-products entries into a Telegram Markdown message.
class SimilarFormatService
  # @param watch_name [String]
  # @param entries [Array<Hash>] each with :product and :similar keys
  def initialize(watch_name, entries)
    @watch_name = watch_name
    @entries = entries
  end

  # @return [String, nil] formatted message or nil if no entries have similar products
  def call
    sections = @entries.filter_map { |entry| format_entry(entry) }
    return nil if sections.empty?

    ["*[#{@watch_name}]* similar products", *sections].join("\n\n")
  end

  private

  # @param entry [Hash]
  # @return [String, nil]
  def format_entry(entry)
    return nil if entry[:similar].empty?

    product = entry[:product]
    header = "*[#{product[:title]}](#{product[:url]})* (#{product[:price]})"
    lines = entry[:similar].each_with_index.map do |s, i|
      "#{i + 1}. #{s[:title]} — #{s[:price]}"
    end
    "#{header}\n#{lines.join("\n")}"
  end
end
