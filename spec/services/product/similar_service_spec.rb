# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../services/product/similar_service'

RSpec.describe Product::SimilarService do
  let(:logger) { instance_double(Logger, info: nil, warn: nil) }
  let(:store) { 'test-store.myshopify.com' }
  let(:params) { { 'store' => store, 'handles' => %w[air-max-90], 'type' => 'products' } }
  let(:showroom_client) { instance_double(ShowroomClient) }
  let(:notifier) { instance_double(DebugNotifier, deliver: nil) }

  before do
    allow(ShowroomClient).to receive(:new).and_return(showroom_client)
    allow(Notifier).to receive(:build).and_return(notifier)
  end

  describe '#call' do
    let(:similar_product) do
      double('ProductSuggestion', title: 'Air Max 95', handle: 'air-max-95', price: '180.00')
    end
    let(:product) do
      double('Product', title: 'Air Max 90', handle: 'air-max-90',
                        price: '150.00', url: 'https://store.com/products/air-max-90',
                        similar: [similar_product])
    end

    before do
      allow(showroom_client).to receive(:find_product).with('air-max-90').and_return(product)
    end

    it 'returns a result hash with status ok' do
      result = described_class.new('sneakers', params, logger).call

      expect(result).to eq(watch_name: 'sneakers', type: 'similar', status: 'ok')
    end

    it 'sends a notification with formatted similar products' do
      described_class.new('sneakers', params, logger).call

      expect(notifier).to have_received(:deliver).with(a_string_including('Air Max 95'))
    end

    it 'skips products that are not found' do
      allow(showroom_client).to receive(:find_product).with('air-max-90')
                                                      .and_raise(Showroom::NotFound.new('not-found', status: 404))

      result = described_class.new('sneakers', params, logger).call

      expect(result[:status]).to eq('ok')
      expect(notifier).not_to have_received(:deliver)
    end

    it 'does not notify when no products have similar results' do
      allow(product).to receive(:similar).and_return([])

      described_class.new('sneakers', params, logger).call

      expect(notifier).not_to have_received(:deliver)
    end
  end
end
