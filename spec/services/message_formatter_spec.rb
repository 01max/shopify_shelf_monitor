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

  let(:product_with_image) do
    product.merge('image' => 'https://cdn.shopify.com/air-max-90.jpg')
  end

  describe '.format' do
    it 'returns nil text and empty photos for an empty diff' do
      result = described_class.format('my_watch', empty_diff)

      expect(result[:text]).to be_nil
      expect(result[:photos]).to be_empty
    end

    it 'includes the watch name in the header' do
      diff = empty_diff.merge(new_products: [product])
      result = described_class.format('favorite_sneakers', diff)

      expect(result[:text]).to include('*[favorite_sneakers]*')
    end

    it 'formats new products without images as text' do
      diff = empty_diff.merge(new_products: [product])
      result = described_class.format('my_watch', diff)

      expect(result[:text]).to include('[Air Max 90](https://store.myshopify.com/products/air-max-90)')
      expect(result[:text]).to include('120.00')
      expect(result[:photos]).to be_empty
    end

    it 'returns photo entries for new products with images' do
      diff = empty_diff.merge(new_products: [product_with_image])
      result = described_class.format('my_watch', diff)

      expect(result[:photos].size).to eq(1)
      expect(result[:photos].first[:image_url]).to eq('https://cdn.shopify.com/air-max-90.jpg')
      expect(result[:photos].first[:caption]).to include('Air Max 90')
      expect(result[:photos].first[:caption]).to include('120.00')
    end

    it 'excludes products with images from the text section' do
      diff = empty_diff.merge(new_products: [product_with_image])
      result = described_class.format('my_watch', diff)

      expect(result[:text]).to be_nil
    end

    it 'includes products without images in text alongside photo products' do
      diff = empty_diff.merge(new_products: [product_with_image,
                                             product.merge('handle' => 'no-img', 'title' => 'No Img')])
      result = described_class.format('my_watch', diff)

      expect(result[:photos].size).to eq(1)
      expect(result[:text]).to include('No Img')
      expect(result[:text]).not_to include('Air Max 90')
    end

    it 'formats price changes' do
      change = ChangeDetector::Change.new(
        handle: 'air-max-90', field: 'price',
        previous_value: '130.00', current_value: '120.00'
      )
      diff = empty_diff.merge(changes: [change])
      result = described_class.format('my_watch', diff)

      expect(result[:text]).to include('air-max-90: price `130.00` → `120.00`')
    end

    it 'formats availability changes' do
      change = ChangeDetector::Change.new(
        handle: 'air-max-90', field: 'available',
        previous_value: true, current_value: false
      )
      diff = empty_diff.merge(changes: [change])
      result = described_class.format('my_watch', diff)

      expect(result[:text]).to include('air-max-90: available `true` → `false`')
    end

    it 'formats variant-level changes' do
      change = ChangeDetector::Change.new(
        handle: 'air-max-90', field: 'variant[Size 10].price',
        previous_value: '130.00', current_value: '120.00'
      )
      diff = empty_diff.merge(changes: [change])
      result = described_class.format('my_watch', diff)

      expect(result[:text]).to include('variant[Size 10].price `130.00` → `120.00`')
    end

    it 'formats removed products' do
      diff = empty_diff.merge(removed_products: [product])
      result = described_class.format('my_watch', diff)

      expect(result[:text]).to include("*Removed products:*\n- air-max-90")
    end

    it 'combines all sections' do
      change = ChangeDetector::Change.new(
        handle: 'ultraboost', field: 'price',
        previous_value: '180.00', current_value: '160.00'
      )
      removed = { 'handle' => 'old-shoe', 'title' => 'Old Shoe' }
      diff = { new_products: [product], changes: [change], removed_products: [removed] }
      result = described_class.format('my_watch', diff)

      expect(result[:text]).to include('*New products:*')
      expect(result[:text]).to include('*Changes:*')
      expect(result[:text]).to include('*Removed products:*')
    end

    it 'falls back to text summary when new products exceed DETAIL_LIMIT' do
      products = (1..11).map do |i|
        { 'handle' => "product-#{i}", 'title' => "Product #{i}",
          'price' => '10.00', 'available' => true,
          'url' => "https://store.myshopify.com/products/product-#{i}",
          'image' => "https://cdn.shopify.com/product-#{i}.jpg" }
      end
      diff = empty_diff.merge(new_products: products)
      result = described_class.format('my_watch', diff)

      expect(result[:photos]).to be_empty
      expect(result[:text]).to include('11 products added')
    end
  end
end
