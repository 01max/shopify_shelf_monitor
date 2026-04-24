# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../services/telegram/chat_service'

RSpec.describe Telegram::ChatService do
  let(:bot_token) { 'test_token' }
  let(:chat_id)   { '123456' }
  let(:api_url)   { "https://api.telegram.org/bot#{bot_token}/sendMessage" }

  before do
    stub_const('ENV', ENV.to_h.merge('TELEGRAM_BOT_TOKEN' => bot_token,
                                     'TELEGRAM_DEFAULT_CHAT_ID' => chat_id))
  end

  describe '#deliver' do
    subject(:service) { described_class.new }

    it 'posts to the Telegram sendMessage endpoint' do
      stub_request(:post, api_url).to_return(status: 200, body: '{"ok":true}')

      service.deliver('Hello!')

      expect(WebMock).to have_requested(:post, api_url)
    end

    it 'sends the correct body fields' do
      stub_request(:post, api_url).to_return(status: 200, body: '{"ok":true}')

      service.deliver('Hello!', parse_mode: 'HTML')

      expect(WebMock).to have_requested(:post, api_url).with(
        body: hash_including('chat_id' => chat_id, 'text' => 'Hello!', 'parse_mode' => 'HTML')
      )
    end

    it 'includes reply_markup as JSON when provided' do
      stub_request(:post, api_url).to_return(status: 200, body: '{"ok":true}')
      markup = { inline_keyboard: [[{ text: 'Book', url: 'https://example.com' }]] }

      service.deliver('Hello!', reply_markup: markup)

      expect(WebMock).to have_requested(:post, api_url).with(
        body: hash_including('reply_markup' => markup.to_json)
      )
    end

    context 'when the message exceeds MAX_MESSAGE_LENGTH' do
      it 'splits into multiple requests' do
        stub_request(:post, api_url).to_return(status: 200, body: '{"ok":true}')
        long_text = "#{'a' * 100}\n" * 50 # ~5050 chars, splits into 2

        service.deliver(long_text)

        expect(WebMock).to have_requested(:post, api_url).twice
      end

      it 'attaches reply_markup only to the last chunk' do
        stub_request(:post, api_url).to_return(status: 200, body: '{"ok":true}')
        long_text = "#{'a' * 100}\n" * 50
        markup = { inline_keyboard: [[{ text: 'View', url: 'https://example.com' }]] }

        service.deliver(long_text, reply_markup: markup)

        expect(WebMock).to have_requested(:post, api_url).with(
          body: hash_including('reply_markup' => markup.to_json)
        ).once
      end
    end

    it 'omits reply_markup when not provided' do
      stub_request(:post, api_url).to_return(status: 200, body: '{"ok":true}')

      service.deliver('Hello!')

      expect(WebMock).not_to have_requested(:post, api_url).with(
        body: hash_including('reply_markup' => anything)
      )
    end

    context 'with a custom chat_id' do
      subject(:service) { described_class.new(chat_id: '999') }

      it 'uses the provided chat_id' do
        stub_request(:post, api_url).to_return(status: 200, body: '{"ok":true}')

        service.deliver('Hello!')

        expect(WebMock).to have_requested(:post, api_url).with(
          body: hash_including('chat_id' => '999')
        )
      end
    end
  end

  describe '#send_media_group' do
    subject(:service) { described_class.new }

    let(:media_api_url) { "https://api.telegram.org/bot#{bot_token}/sendMediaGroup" }
    let(:photo_urls) { %w[https://cdn.example.com/a.jpg https://cdn.example.com/b.jpg] }

    it 'posts to the Telegram sendMediaGroup endpoint with photo media JSON' do
      stub_request(:post, media_api_url).to_return(status: 200, body: '{"ok":true}')

      service.send_media_group(photo_urls)

      expected_media = [{ type: 'photo', media: photo_urls[0] },
                        { type: 'photo', media: photo_urls[1] }]
      expect(WebMock).to have_requested(:post, media_api_url).with(
        body: hash_including('chat_id' => chat_id, 'media' => expected_media.to_json)
      )
    end

    it 'raises on API error' do
      stub_request(:post, media_api_url).to_return(status: 400, body: '{"ok":false}')

      expect { service.send_media_group(photo_urls) }
        .to raise_error(/Telegram API error/)
    end
  end

  describe '.build_inline_keyboard' do
    it 'returns nil for nil input' do
      expect(described_class.build_inline_keyboard(nil)).to be_nil
    end

    it 'returns nil for empty array' do
      expect(described_class.build_inline_keyboard([])).to be_nil
    end

    it 'wraps a flat array of buttons into a single row' do
      buttons = [{ text: 'View', url: 'https://example.com' }]
      result = described_class.build_inline_keyboard(buttons)

      expect(result).to eq(inline_keyboard: [buttons])
    end

    it 'passes through an array of arrays unchanged' do
      buttons = [[{ text: 'A', url: 'https://a.com' }], [{ text: 'B', url: 'https://b.com' }]]
      result = described_class.build_inline_keyboard(buttons)

      expect(result).to eq(inline_keyboard: buttons)
    end
  end
end
