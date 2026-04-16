# frozen_string_literal: true

require 'spec_helper'
require_relative '../../services/showroom_client'

RSpec.describe ShowroomClient do
  let(:logger) { instance_double(Logger, debug: nil, warn: nil) }
  let(:store) { 'test-store.myshopify.com' }
  let(:showroom_client) { instance_double(Showroom::Client) }

  subject(:client) { described_class.new(store: store, rate_limit_ms: 0, logger: logger) }

  before do
    allow(Showroom::Client).to receive(:new).with(store: store).and_return(showroom_client)
    allow(client).to receive(:sleep)
  end

  describe '#find_product' do
    let(:product) { double('Product', handle: 'air-max-90') }

    it 'delegates to the Showroom client' do
      allow(showroom_client).to receive(:product).with('air-max-90').and_return(product)

      result = client.find_product('air-max-90')

      expect(result).to eq(product)
    end

    it 'raises Showroom::NotFound when product does not exist' do
      allow(showroom_client).to receive(:product).and_raise(Showroom::NotFound.new('not-found', status: 404))

      expect { client.find_product('not-found') }.to raise_error(Showroom::NotFound)
    end

    it 'retries once on TooManyRequests' do
      call_count = 0
      allow(showroom_client).to receive(:product) do
        call_count += 1
        raise Showroom::TooManyRequests.new('rate limited', status: 429) if call_count == 1

        product
      end

      result = client.find_product('air-max-90')

      expect(result).to eq(product)
      expect(call_count).to eq(2)
    end

    it 'logs a warning on TooManyRequests' do
      call_count = 0
      allow(showroom_client).to receive(:product) do
        call_count += 1
        raise Showroom::TooManyRequests.new('rate limited', status: 429) if call_count == 1

        product
      end

      client.find_product('air-max-90')

      expect(logger).to have_received(:warn).with(/Rate limited/)
    end
  end

  describe '#find_collection' do
    let(:collection) { double('Collection', handle: 'new-arrivals') }

    it 'delegates to the Showroom client' do
      allow(showroom_client).to receive(:collection).with('new-arrivals').and_return(collection)

      result = client.find_collection('new-arrivals')

      expect(result).to eq(collection)
    end
  end

  describe '#collection_products' do
    let(:collection) { double('Collection') }
    let(:product_a) { double('ProductA', handle: 'product-a') }
    let(:product_b) { double('ProductB', handle: 'product-b') }

    it 'fetches all products across pages' do
      allow(collection).to receive(:products).with(limit: 250, page: 1).and_return([product_a, product_b])
      allow(collection).to receive(:products).with(limit: 250, page: 2).and_return([])

      result = client.collection_products(collection)

      expect(result).to eq([product_a, product_b])
    end

    it 'handles multiple pages' do
      allow(collection).to receive(:products).with(limit: 250, page: 1).and_return([product_a])
      allow(collection).to receive(:products).with(limit: 250, page: 2).and_return([product_b])
      allow(collection).to receive(:products).with(limit: 250, page: 3).and_return([])

      result = client.collection_products(collection)

      expect(result).to eq([product_a, product_b])
    end

    it 'returns empty array for empty collection' do
      allow(collection).to receive(:products).with(limit: 250, page: 1).and_return([])

      result = client.collection_products(collection)

      expect(result).to eq([])
    end
  end

  describe 'rate limiting' do
    it 'sleeps between requests' do
      product = double('Product')
      allow(showroom_client).to receive(:product).and_return(product)

      rate_limited_client = described_class.new(store: store, rate_limit_ms: 100, logger: logger)
      allow(rate_limited_client).to receive(:sleep)

      rate_limited_client.find_product('test')

      expect(rate_limited_client).to have_received(:sleep).with(0.1)
    end
  end
end
