# frozen_string_literal: true

# Compares current product snapshots against previous ones and returns a structured diff.
# Pure logic — no side effects, no API calls, no notifications.
class ChangeDetector
  Change = Data.define(:handle, :field, :previous_value, :current_value)
  TRACKED_FIELDS = %w[price available].freeze

  # @param current_products [Array<Hash>] current product snapshots
  # @param previous_products [Array<Hash>] previous product snapshots (from report)
  # @return [Hash] { new_products: [...], removed_products: [...], changes: [...] }
  def self.detect(current_products, previous_products)
    current_by_handle = index_by_handle(current_products)
    previous_by_handle = index_by_handle(previous_products)

    {
      new_products: handles_diff(current_by_handle, previous_by_handle),
      removed_products: handles_diff(previous_by_handle, current_by_handle),
      changes: detect_changes(current_by_handle, previous_by_handle)
    }
  end

  def self.index_by_handle(products)
    products.to_h { |p| [p['handle'], p] }
  end

  def self.handles_diff(source, other)
    (source.keys - other.keys).map { |h| source[h] }
  end

  def self.detect_changes(current_by_handle, previous_by_handle)
    (current_by_handle.keys & previous_by_handle.keys).flat_map do |handle|
      diff_product(current_by_handle[handle], previous_by_handle[handle])
    end
  end

  # @param current [Hash] single product snapshot
  # @param previous [Hash] single product snapshot
  # @return [Array<Change>]
  def self.diff_product(current, previous)
    handle = current['handle']
    changes = diff_fields(handle, current, previous)
    changes.concat(diff_variants(handle, current.fetch('variants', []), previous.fetch('variants', [])))
  end

  def self.diff_fields(handle, current, previous, prefix: nil)
    TRACKED_FIELDS.filter_map do |field|
      next if current[field] == previous[field]

      field_name = prefix ? "#{prefix}.#{field}" : field
      Change.new(handle: handle, field: field_name,
                 previous_value: previous[field], current_value: current[field])
    end
  end

  def self.diff_variants(handle, current_variants, previous_variants)
    current_by_title = current_variants.to_h { |v| [v['title'], v] }
    previous_by_title = previous_variants.to_h { |v| [v['title'], v] }

    (current_by_title.keys & previous_by_title.keys).flat_map do |title|
      diff_fields(handle, current_by_title[title], previous_by_title[title], prefix: "variant[#{title}]")
    end
  end

  private_class_method :index_by_handle, :handles_diff, :detect_changes,
                       :diff_product, :diff_fields, :diff_variants
end
