# frozen_string_literal: true

require 'spec_helper'
require_relative '../../services/product_watch_service'

RSpec.describe ProductWatchService do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, debug: nil) }
  let(:chat_service) { instance_double(Telegram::ChatService, deliver: nil, send_media_group: nil) }
  let(:client) { instance_double(ShowroomClient) }

  let(:params) do
    { 'type' => 'products', 'store' => 'test.myshopify.com', 'handles' => %w[air-max-90 ultraboost] }
  end

  let(:variant) { double('Variant', title: 'Size 10', price: '120.00', available?: true) }
  let(:product) do
    double('Product', handle: 'air-max-90', title: 'Air Max 90', price: '120.00',
                      available?: true, url: 'https://test.myshopify.com/products/air-max-90',
                      main_image: nil, variants: [variant])
  end
  let(:product2) do
    double('Product2', handle: 'ultraboost', title: 'Ultraboost', price: '180.00',
                       available?: true, url: 'https://test.myshopify.com/products/ultraboost',
                       main_image: nil, variants: [])
  end

  before do
    allow(ShowroomClient).to receive(:new).and_return(client)
    allow(Telegram::ChatService).to receive(:new).and_return(chat_service)
    allow(client).to receive(:find_product).with('air-max-90').and_return(product)
    allow(client).to receive(:find_product).with('ultraboost').and_return(product2)
    stub_const('ENV', ENV.to_h.merge('TELEGRAM_BOT_TOKEN' => 'token',
                                     'TELEGRAM_DEFAULT_CHAT_ID' => '123'))
  end

  describe '#call' do
    context 'on first run (no previous data)' do
      it 'detects all products as new and sends notification' do
        described_class.new('my_watch', params, logger).call

        expect(chat_service).to have_received(:deliver).with(/changes detected/)
      end

      it 'returns a result hash with product snapshots' do
        result = described_class.new('my_watch', params, logger).call

        expect(result[:watch_name]).to eq('my_watch')
        expect(result[:type]).to eq('products')
        expect(result[:status]).to eq('ok')
        expect(result[:products].size).to eq(2)
      end
    end

    context 'when nothing changed' do
      let(:previous_products) do
        [
          { 'handle' => 'air-max-90', 'title' => 'Air Max 90', 'price' => '120.00',
            'available' => true, 'url' => 'https://test.myshopify.com/products/air-max-90',
            'variants' => [{ 'title' => 'Size 10', 'price' => '120.00', 'available' => true }] },
          { 'handle' => 'ultraboost', 'title' => 'Ultraboost', 'price' => '180.00',
            'available' => true, 'url' => 'https://test.myshopify.com/products/ultraboost',
            'variants' => [] }
        ]
      end

      it 'does not send a notification' do
        described_class.new('my_watch', params, logger, previous_products).call

        expect(chat_service).not_to have_received(:deliver)
      end
    end

    context 'when a price changed' do
      let(:previous_products) do
        [
          { 'handle' => 'air-max-90', 'title' => 'Air Max 90', 'price' => '130.00',
            'available' => true, 'url' => 'https://test.myshopify.com/products/air-max-90',
            'variants' => [{ 'title' => 'Size 10', 'price' => '120.00', 'available' => true }] },
          { 'handle' => 'ultraboost', 'title' => 'Ultraboost', 'price' => '180.00',
            'available' => true, 'url' => 'https://test.myshopify.com/products/ultraboost',
            'variants' => [] }
        ]
      end

      it 'sends a notification with the change' do
        described_class.new('my_watch', params, logger, previous_products).call

        expect(chat_service).to have_received(:deliver).with(/price/)
      end
    end

    context 'when a product is not found' do
      before do
        allow(client).to receive(:find_product).with('ultraboost')
                     .and_raise(Showroom::NotFound.new('ultraboost', status: 404))
      end

      it 'logs a warning and continues' do
        described_class.new('my_watch', params, logger).call

        expect(logger).to have_received(:warn).with(/ultraboost.*not found/)
      end

      it 'returns only the found products' do
        result = described_class.new('my_watch', params, logger).call

        expect(result[:products].size).to eq(1)
        expect(result[:products].first['handle']).to eq('air-max-90')
      end
    end

    context 'with FORCE_NOTIFY=true and no changes' do
      let(:previous_products) do
        [
          { 'handle' => 'air-max-90', 'title' => 'Air Max 90', 'price' => '120.00',
            'available' => true, 'url' => 'https://test.myshopify.com/products/air-max-90',
            'variants' => [{ 'title' => 'Size 10', 'price' => '120.00', 'available' => true }] },
          { 'handle' => 'ultraboost', 'title' => 'Ultraboost', 'price' => '180.00',
            'available' => true, 'url' => 'https://test.myshopify.com/products/ultraboost',
            'variants' => [] }
        ]
      end

      before do
        stub_const('ENV', ENV.to_h.merge('TELEGRAM_BOT_TOKEN' => 'token',
                                         'TELEGRAM_DEFAULT_CHAT_ID' => '123',
                                         'FORCE_NOTIFY' => 'true'))
      end

      it 'sends a notification even when nothing changed' do
        described_class.new('my_watch', params, logger, previous_products).call

        expect(chat_service).to have_received(:deliver).with(/no changes detected/)
      end
    end

    context 'with a custom telegram_chat_id' do
      let(:params_with_chat) { params.merge('telegram_chat_id' => '999') }

      it 'passes the chat_id to the Telegram service' do
        described_class.new('my_watch', params_with_chat, logger).call

        expect(Telegram::ChatService).to have_received(:new).with(chat_id: '999')
      end
    end
  end
end
