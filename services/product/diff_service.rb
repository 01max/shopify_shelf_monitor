# frozen_string_literal: true

# Compares current product snapshots against previous ones and returns a structured diff.
# Pure logic, no side effects, no API calls, no notifications.
module Product
  # Product::DiffService
  class DiffService
    # Immutable value object representing a single field change on a product or variant.
    ProductChange = Data.define(:handle, :title, :url, :image, :field, :previous_value, :current_value)

    # Product/variant fields compared across snapshots.
    TRACKED_FIELDS = %w[price available].freeze

    # @param current_products [Array<Hash>] current product snapshots
    # @param previous_products [Array<Hash>] previous product snapshots (from report)
    def initialize(current_products, previous_products)
      @current_by_handle = index_by_handle(current_products)
      @previous_by_handle = index_by_handle(previous_products)
    end

    # @return [Hash] with :new_products, :removed_products, :changes keys
    def call
      {
        new_products: handles_diff(@current_by_handle, @previous_by_handle),
        removed_products: handles_diff(@previous_by_handle, @current_by_handle),
        changes: detect_changes
      }
    end

    private

    # @param products [Array<Hash>]
    # @return [Hash{String => Hash}]
    def index_by_handle(products)
      products.to_h { |p| [p['handle'], p] }
    end

    # @param source [Hash{String => Hash}]
    # @param other [Hash{String => Hash}]
    # @return [Array<Hash>] products in source but not in other
    def handles_diff(source, other)
      (source.keys - other.keys).map { |h| source[h] }
    end

    # @return [Array<ProductChange>]
    def detect_changes
      (@current_by_handle.keys & @previous_by_handle.keys).flat_map do |handle|
        diff_product(@current_by_handle[handle], @previous_by_handle[handle])
      end
    end

    # @param current [Hash] single product snapshot
    # @param previous [Hash] single product snapshot
    # @return [Array<ProductChange>]
    def diff_product(current, previous)
      handle = current['handle']
      title = current['title']
      url = current['url']
      image = current['image']
      changes = diff_fields(handle, title, url, image, current, previous)
      changes.concat(diff_variants(handle, title, url, image, current.fetch('variants', []),
                                   previous.fetch('variants', [])))
    end

    # @param handle [String]
    # @param title [String]
    # @param url [String]
    # @param image [String, nil]
    # @param current [Hash]
    # @param previous [Hash]
    # @param prefix [String, nil] field name prefix for variant fields
    # @return [Array<ProductChange>]
    def diff_fields(handle, title, url, image, current, previous, prefix: nil)
      TRACKED_FIELDS.filter_map do |field|
        next if current[field] == previous[field]

        field_name = prefix ? "#{prefix}.#{field}" : field
        ProductChange.new(handle: handle, title: title, url: url, image: image,
                          field: field_name, previous_value: previous[field], current_value: current[field])
      end
    end

    # @param handle [String]
    # @param title [String]
    # @param url [String]
    # @param image [String, nil]
    # @param current_variants [Array<Hash>]
    # @param previous_variants [Array<Hash>]
    # @return [Array<ProductChange>]
    def diff_variants(handle, title, url, image, current_variants, previous_variants)
      current_by_title = current_variants.to_h { |v| [v['title'], v] }
      previous_by_title = previous_variants.to_h { |v| [v['title'], v] }

      (current_by_title.keys & previous_by_title.keys).flat_map do |vtitle|
        diff_fields(handle, title, url, image, current_by_title[vtitle], previous_by_title[vtitle],
                    prefix: "variant[#{vtitle}]")
      end
    end
  end
end
