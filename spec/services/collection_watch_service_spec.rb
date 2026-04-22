# frozen_string_literal: true

require 'spec_helper'
require_relative '../../services/collection_watch_service'

RSpec.describe CollectionWatchService do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, debug: nil) }
  let(:chat_service) { instance_double(Telegram::ChatService, deliver: nil, send_media_group: nil) }
  let(:client) { instance_double(ShowroomClient) }
  let(:collection) { double('Collection', handle: 'new-arrivals') }

  let(:params) do
    { 'type' => 'collection', 'store' => 'test.myshopify.com', 'handle' => 'new-arrivals' }
  end

  let(:variant) { double('Variant', title: 'Size 10', price: '120.00', available?: true) }
  let(:product_a) do
    double('ProductA', handle: 'air-max-90', title: 'Air Max 90', price: '120.00',
                       available?: true, url: 'https://test.myshopify.com/products/air-max-90',
                       main_image: nil, variants: [variant])
  end
  let(:product_b) do
    double('ProductB', handle: 'ultraboost', title: 'Ultraboost', price: '180.00',
                       available?: true, url: 'https://test.myshopify.com/products/ultraboost',
                       main_image: nil, variants: [])
  end

  let(:snapshot_a) do
    { 'handle' => 'air-max-90', 'title' => 'Air Max 90', 'price' => '120.00',
      'available' => true, 'url' => 'https://test.myshopify.com/products/air-max-90',
      'variants' => [{ 'title' => 'Size 10', 'price' => '120.00', 'available' => true }] }
  end
  let(:snapshot_b) do
    { 'handle' => 'ultraboost', 'title' => 'Ultraboost', 'price' => '180.00',
      'available' => true, 'url' => 'https://test.myshopify.com/products/ultraboost',
      'variants' => [] }
  end

  before do
    allow(ShowroomClient).to receive(:new).and_return(client)
    allow(Telegram::ChatService).to receive(:new).and_return(chat_service)
    allow(client).to receive(:find_collection).with('new-arrivals').and_return(collection)
    allow(client).to receive(:collection_products).with(collection).and_return([product_a, product_b])
    stub_const('ENV', ENV.to_h.merge('TELEGRAM_BOT_TOKEN' => 'token',
                                     'TELEGRAM_DEFAULT_CHAT_ID' => '123'))
  end

  describe '#call' do
    context 'on first run (no previous data)' do
      it 'detects all products as new and sends notification' do
        described_class.new('my_watch', params, logger).call

        expect(chat_service).to have_received(:deliver).with(/changes detected/)
      end

      it 'returns a result hash with products and count' do
        result = described_class.new('my_watch', params, logger).call

        expect(result[:watch_name]).to eq('my_watch')
        expect(result[:type]).to eq('collection')
        expect(result[:status]).to eq('ok')
        expect(result[:products].size).to eq(2)
        expect(result[:products_count]).to eq(2)
      end
    end

    context 'when nothing changed' do
      it 'does not send a notification' do
        described_class.new('my_watch', params, logger, [snapshot_a, snapshot_b]).call

        expect(chat_service).not_to have_received(:deliver)
      end
    end

    context 'when a new product is added to the collection' do
      it 'sends a notification about the new product' do
        described_class.new('my_watch', params, logger, [snapshot_a]).call

        expect(chat_service).to have_received(:deliver).with(/New products.*Ultraboost/m)
      end
    end

    context 'when a product is removed from the collection' do
      let(:old_product) do
        { 'handle' => 'old-shoe', 'title' => 'Old Shoe', 'price' => '90.00',
          'available' => true, 'url' => 'https://test.myshopify.com/products/old-shoe',
          'variants' => [] }
      end

      it 'sends a notification about the removed product' do
        described_class.new('my_watch', params, logger, [snapshot_a, snapshot_b, old_product]).call

        expect(chat_service).to have_received(:deliver).with(/Removed products.*old-shoe/m)
      end
    end

    context 'when a product price changed' do
      let(:previous_with_different_price) do
        [snapshot_a.merge('price' => '130.00'), snapshot_b]
      end

      it 'sends a notification with the change' do
        described_class.new('my_watch', params, logger, previous_with_different_price).call

        expect(chat_service).to have_received(:deliver).with(/price/)
      end
    end

    context 'when the collection is not found' do
      before do
        allow(client).to receive(:find_collection)
                     .and_raise(Showroom::NotFound.new('new-arrivals', status: 404))
      end

      it 'lets the error propagate' do
        expect { described_class.new('my_watch', params, logger).call }
          .to raise_error(Showroom::NotFound)
      end
    end

    context 'with FORCE_NOTIFY=true and no changes' do
      before do
        stub_const('ENV', ENV.to_h.merge('TELEGRAM_BOT_TOKEN' => 'token',
                                         'TELEGRAM_DEFAULT_CHAT_ID' => '123',
                                         'FORCE_NOTIFY' => 'true'))
      end

      it 'sends a notification even when nothing changed' do
        described_class.new('my_watch', params, logger, [snapshot_a, snapshot_b]).call

        expect(chat_service).to have_received(:deliver).with(/no changes detected/)
      end
    end
  end
end
