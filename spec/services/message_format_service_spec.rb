# frozen_string_literal: true

require 'spec_helper'
require_relative '../../services/message_format_service'

RSpec.describe MessageFormatService do
  let(:empty_diff) { { new_products: [], removed_products: [], changes: [] } }

  let(:product) do
    { 'handle' => 'air-max-90', 'title' => 'Air Max 90',
      'price' => '120.00', 'available' => true,
      'url' => 'https://store.myshopify.com/products/air-max-90' }
  end

  let(:product_with_image) do
    product.merge('image' => 'https://cdn.shopify.com/air-max-90.jpg')
  end

  describe '#call' do
    it 'returns nil text and empty photo_urls for an empty diff' do
      result = described_class.new('my_watch', empty_diff).call

      expect(result[:text]).to be_nil
      expect(result[:photo_urls]).to be_empty
    end

    it 'includes the watch name in the header' do
      diff = empty_diff.merge(new_products: [product])
      result = described_class.new('favorite_sneakers', diff).call

      expect(result[:text]).to include('*[favorite_sneakers]*')
    end

    it 'omits pagination suffix when total_pages is 1' do
      diff = empty_diff.merge(new_products: [product])
      result = described_class.new('my_watch', diff, page: 1, total_pages: 1).call

      expect(result[:text]).not_to match(%r{\(\d+/\d+\)})
    end

    it 'appends page indicator when total_pages > 1' do
      diff = empty_diff.merge(new_products: [product])
      result = described_class.new('my_watch', diff, page: 2, total_pages: 3).call

      expect(result[:text]).to include('changes detected (2/3)')
    end

    it 'formats new products as a numbered list' do
      diff = empty_diff.merge(new_products: [product])
      result = described_class.new('my_watch', diff).call

      expect(result[:text]).to include('1. [Air Max 90](https://store.myshopify.com/products/air-max-90) : 120.00')
    end

    it 'numbers multiple new products in order' do
      product_b = { 'handle' => 'ultraboost', 'title' => 'Ultraboost',
                    'price' => '180.00', 'available' => true,
                    'url' => 'https://store.myshopify.com/products/ultraboost' }
      diff = empty_diff.merge(new_products: [product, product_b])
      result = described_class.new('my_watch', diff).call

      expect(result[:text]).to include('1. [Air Max 90]')
      expect(result[:text]).to include('2. [Ultraboost]')
    end

    it 'returns photo_urls for new products with images' do
      diff = empty_diff.merge(new_products: [product_with_image])
      result = described_class.new('my_watch', diff).call

      expect(result[:photo_urls]).to eq(['https://cdn.shopify.com/air-max-90.jpg'])
    end

    it 'includes products with images in the text list too' do
      diff = empty_diff.merge(new_products: [product_with_image])
      result = described_class.new('my_watch', diff).call

      expect(result[:text]).to include('1. [Air Max 90]')
    end

    it 'preserves order between photo_urls and text list' do
      product_no_img = { 'handle' => 'no-img', 'title' => 'No Img',
                         'price' => '50.00', 'available' => true,
                         'url' => 'https://store.myshopify.com/products/no-img' }
      product_b_img = { 'handle' => 'ultraboost', 'title' => 'Ultraboost',
                        'price' => '180.00', 'available' => true,
                        'url' => 'https://store.myshopify.com/products/ultraboost',
                        'image' => 'https://cdn.shopify.com/ultraboost.jpg' }
      diff = empty_diff.merge(new_products: [product_with_image, product_no_img, product_b_img])
      result = described_class.new('my_watch', diff).call

      expect(result[:photo_urls]).to eq(%w[
                                          https://cdn.shopify.com/air-max-90.jpg
                                          https://cdn.shopify.com/ultraboost.jpg
                                        ])
      expect(result[:text]).to include('1. [Air Max 90]')
      expect(result[:text]).to include('2. [No Img]')
      expect(result[:text]).to include('3. [Ultraboost]')
    end

    it 'returns empty photo_urls for products without images' do
      diff = empty_diff.merge(new_products: [product])
      result = described_class.new('my_watch', diff).call

      expect(result[:photo_urls]).to be_empty
    end

    it 'formats price changes with title and url' do
      change = Product::DiffService::ProductChange.new(
        handle: 'air-max-90', title: 'Air Max 90',
        url: 'https://store.myshopify.com/products/air-max-90', image: nil,
        field: 'price', previous_value: '130.00', current_value: '120.00'
      )
      diff = empty_diff.merge(changes: [change])
      result = described_class.new('my_watch', diff).call

      expect(result[:text]).to include('[Air Max 90](https://store.myshopify.com/products/air-max-90):')
      expect(result[:text]).to include('  - price: `130.00` → `120.00`')
    end

    it 'formats availability changes' do
      change = Product::DiffService::ProductChange.new(
        handle: 'air-max-90', title: 'Air Max 90',
        url: 'https://store.myshopify.com/products/air-max-90', image: nil,
        field: 'available', previous_value: true, current_value: false
      )
      diff = empty_diff.merge(changes: [change])
      result = described_class.new('my_watch', diff).call

      expect(result[:text]).to include('  - available: `true` → `false`')
    end

    it 'formats variant-level changes' do
      change = Product::DiffService::ProductChange.new(
        handle: 'air-max-90', title: 'Air Max 90',
        url: 'https://store.myshopify.com/products/air-max-90', image: nil,
        field: 'variant[Size 10].price', previous_value: '130.00', current_value: '120.00'
      )
      diff = empty_diff.merge(changes: [change])
      result = described_class.new('my_watch', diff).call

      expect(result[:text]).to include('  - variant[Size 10].price: `130.00` → `120.00`')
    end

    it 'groups multiple changes for the same product under one header' do
      changes = [
        Product::DiffService::ProductChange.new(
          handle: 'air-max-90', title: 'Air Max 90',
          url: 'https://store.myshopify.com/products/air-max-90', image: nil,
          field: 'price', previous_value: '130.00', current_value: '120.00'
        ),
        Product::DiffService::ProductChange.new(
          handle: 'air-max-90', title: 'Air Max 90',
          url: 'https://store.myshopify.com/products/air-max-90', image: nil,
          field: 'variant[Size 10].price', previous_value: '130.00', current_value: '120.00'
        )
      ]
      diff = empty_diff.merge(changes: changes)
      result = described_class.new('my_watch', diff).call

      expect(result[:text].scan('[Air Max 90]').size).to eq(1)
      expect(result[:text]).to include('  - price:')
      expect(result[:text]).to include('  - variant[Size 10].price:')
    end

    it 'returns photo_urls for changed products with images' do
      change = Product::DiffService::ProductChange.new(
        handle: 'air-max-90', title: 'Air Max 90',
        url: 'https://store.myshopify.com/products/air-max-90',
        image: 'https://cdn.shopify.com/air-max-90.jpg',
        field: 'price', previous_value: '130.00', current_value: '120.00'
      )
      diff = empty_diff.merge(changes: [change])
      result = described_class.new('my_watch', diff).call

      expect(result[:photo_urls]).to eq(['https://cdn.shopify.com/air-max-90.jpg'])
    end

    it 'formats removed products' do
      diff = empty_diff.merge(removed_products: [product])
      result = described_class.new('my_watch', diff).call

      expect(result[:text]).to include("*Removed products:*\n- air-max-90")
    end

    it 'combines all sections' do
      change = Product::DiffService::ProductChange.new(
        handle: 'ultraboost', title: 'Ultraboost',
        url: 'https://store.myshopify.com/products/ultraboost', image: nil,
        field: 'price', previous_value: '180.00', current_value: '160.00'
      )
      removed = { 'handle' => 'old-shoe', 'title' => 'Old Shoe' }
      diff = { new_products: [product], changes: [change], removed_products: [removed] }
      result = described_class.new('my_watch', diff).call

      expect(result[:text]).to include('*New products:*')
      expect(result[:text]).to include('*Changes:*')
      expect(result[:text]).to include('*Removed products:*')
    end

    it 'falls back to text summary when new products exceed PRODUCT_COUNT_LIMIT' do
      products = (1..21).map do |i|
        { 'handle' => "product-#{i}", 'title' => "Product #{i}",
          'price' => '10.00', 'available' => true,
          'url' => "https://store.myshopify.com/products/product-#{i}",
          'image' => "https://cdn.shopify.com/product-#{i}.jpg" }
      end
      diff = empty_diff.merge(new_products: products)
      result = described_class.new('my_watch', diff).call

      expect(result[:text]).to include('21 products added')
    end

    it 'returns up to IMAGE_COUNT_LIMIT photo_urls regardless of product count' do
      products = (1..15).map do |i|
        { 'handle' => "product-#{i}", 'title' => "Product #{i}",
          'price' => '10.00', 'available' => true,
          'url' => "https://store.myshopify.com/products/product-#{i}",
          'image' => "https://cdn.shopify.com/product-#{i}.jpg" }
      end
      diff = empty_diff.merge(new_products: products)
      result = described_class.new('my_watch', diff).call

      expect(result[:photo_urls].size).to eq(MessageFormatService::IMAGE_COUNT_LIMIT)
    end
  end
end
