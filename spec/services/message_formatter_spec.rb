# frozen_string_literal: true

require 'spec_helper'
require_relative '../../services/message_formatter'

RSpec.describe MessageFormatter do
  let(:empty_diff) { { new_products: [], removed_products: [], changes: [] } }

  let(:product) do
    { 'handle' => 'air-max-90', 'title' => 'Air Max 90',
      'price' => '120.00', 'available' => true,
      'url' => 'https://store.myshopify.com/products/air-max-90' }
  end

  describe '.format' do
    it 'returns nil for an empty diff' do
      expect(described_class.format('my_watch', empty_diff)).to be_nil
    end

    it 'includes the watch name in the header' do
      diff = empty_diff.merge(new_products: [product])
      result = described_class.format('favorite_sneakers', diff)

      expect(result).to include('*ShelfMonitor [favorite_sneakers]*')
    end

    it 'formats new products with title, URL, and price' do
      diff = empty_diff.merge(new_products: [product])
      result = described_class.format('my_watch', diff)

      expect(result).to include('[Air Max 90](https://store.myshopify.com/products/air-max-90)')
      expect(result).to include('120.00')
    end

    it 'formats price changes' do
      change = ChangeDetector::Change.new(
        handle: 'air-max-90', field: 'price',
        previous_value: '130.00', current_value: '120.00'
      )
      diff = empty_diff.merge(changes: [change])
      result = described_class.format('my_watch', diff)

      expect(result).to include('air-max-90: price `130.00` → `120.00`')
    end

    it 'formats availability changes' do
      change = ChangeDetector::Change.new(
        handle: 'air-max-90', field: 'available',
        previous_value: true, current_value: false
      )
      diff = empty_diff.merge(changes: [change])
      result = described_class.format('my_watch', diff)

      expect(result).to include('air-max-90: available `true` → `false`')
    end

    it 'formats variant-level changes' do
      change = ChangeDetector::Change.new(
        handle: 'air-max-90', field: 'variant[Size 10].price',
        previous_value: '130.00', current_value: '120.00'
      )
      diff = empty_diff.merge(changes: [change])
      result = described_class.format('my_watch', diff)

      expect(result).to include('variant[Size 10].price `130.00` → `120.00`')
    end

    it 'formats removed products' do
      diff = empty_diff.merge(removed_products: [product])
      result = described_class.format('my_watch', diff)

      expect(result).to include("*Removed products:*\n- air-max-90")
    end

    it 'combines all sections' do
      change = ChangeDetector::Change.new(
        handle: 'ultraboost', field: 'price',
        previous_value: '180.00', current_value: '160.00'
      )
      removed = { 'handle' => 'old-shoe', 'title' => 'Old Shoe' }
      diff = { new_products: [product], changes: [change], removed_products: [removed] }
      result = described_class.format('my_watch', diff)

      expect(result).to include('*New products:*')
      expect(result).to include('*Changes:*')
      expect(result).to include('*Removed products:*')
    end
  end
end
