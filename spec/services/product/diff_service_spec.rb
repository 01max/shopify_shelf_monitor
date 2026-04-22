# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../services/product/diff_service'

RSpec.describe Product::DiffService do
  def product(handle: 'air-max-90', title: 'Air Max 90', price: '120.00', available: true, variants: [])
    { 'handle' => handle, 'title' => title, 'price' => price, 'available' => available, 'variants' => variants }
  end

  def variant(title: 'Size 10', price: '120.00', available: true)
    { 'title' => title, 'price' => price, 'available' => available }
  end

  describe '#call' do
    it 'returns empty diff when nothing changed' do
      products = [product]
      diff = described_class.new(products, products).call

      expect(diff[:new_products]).to be_empty
      expect(diff[:removed_products]).to be_empty
      expect(diff[:changes]).to be_empty
    end

    it 'detects a price change' do
      previous = [product(price: '130.00')]
      current = [product(price: '120.00')]

      diff = described_class.new(current, previous).call

      expect(diff[:changes]).to contain_exactly(
        described_class::ProductChange.new(handle: 'air-max-90', field: 'price',
                                           previous_value: '130.00', current_value: '120.00')
      )
    end

    it 'detects an availability change' do
      previous = [product(available: true)]
      current = [product(available: false)]

      diff = described_class.new(current, previous).call

      expect(diff[:changes]).to contain_exactly(
        described_class::ProductChange.new(handle: 'air-max-90', field: 'available',
                                           previous_value: true, current_value: false)
      )
    end

    it 'detects a variant price change' do
      previous = [product(variants: [variant(price: '130.00')])]
      current = [product(variants: [variant(price: '120.00')])]

      diff = described_class.new(current, previous).call

      expect(diff[:changes]).to contain_exactly(
        described_class::ProductChange.new(handle: 'air-max-90', field: 'variant[Size 10].price',
                                           previous_value: '130.00', current_value: '120.00')
      )
    end

    it 'detects a variant availability change' do
      previous = [product(variants: [variant(available: true)])]
      current = [product(variants: [variant(available: false)])]

      diff = described_class.new(current, previous).call

      expect(diff[:changes]).to contain_exactly(
        described_class::ProductChange.new(handle: 'air-max-90', field: 'variant[Size 10].available',
                                           previous_value: true, current_value: false)
      )
    end

    it 'detects a new product' do
      previous = []
      current = [product]

      diff = described_class.new(current, previous).call

      expect(diff[:new_products]).to eq([product])
      expect(diff[:changes]).to be_empty
    end

    it 'detects a removed product' do
      previous = [product]
      current = []

      diff = described_class.new(current, previous).call

      expect(diff[:removed_products]).to eq([product])
      expect(diff[:changes]).to be_empty
    end

    it 'detects multiple changes on the same product' do
      previous = [product(price: '130.00', available: true)]
      current = [product(price: '120.00', available: false)]

      diff = described_class.new(current, previous).call

      expect(diff[:changes].size).to eq(2)
      expect(diff[:changes].map(&:field)).to contain_exactly('price', 'available')
    end

    it 'treats first run as all new products' do
      current = [product, product(handle: 'ultraboost', title: 'Ultraboost')]

      diff = described_class.new(current, []).call

      expect(diff[:new_products].size).to eq(2)
      expect(diff[:changes]).to be_empty
      expect(diff[:removed_products]).to be_empty
    end
  end
end
