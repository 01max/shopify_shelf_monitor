# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../services/telegram/command_poller'

RSpec.describe Telegram::CommandPoller do
  let(:bot_token) { 'test_token' }
  let(:chat_id)   { '123456' }
  let(:api_url)   { "https://api.telegram.org/bot#{bot_token}/getUpdates" }

  before do
    stub_const('ENV', ENV.to_h.merge('TELEGRAM_BOT_TOKEN' => bot_token,
                                     'TELEGRAM_DEFAULT_CHAT_ID' => chat_id))
  end

  def update(update_id:, chat:, text:)
    { 'update_id' => update_id, 'message' => { 'chat' => { 'id' => chat }, 'text' => text } }
  end

  def stub_updates(updates, offset: nil)
    query = offset ? { offset: offset.to_s, timeout: '0' } : { timeout: '0' }
    stub_request(:get, api_url)
      .with(query: query)
      .to_return(status: 200, body: { ok: true, result: updates }.to_json)
  end

  describe '#commands' do
    context 'with a baseline update_id' do
      subject(:poller) { described_class.new(since_update_id: 100) }

      it 'returns [] when no new updates are pending' do
        stub_updates([], offset: 101)

        expect(poller.commands).to eq []
        expect(poller.last_update_id).to eq 100
      end

      it 'returns a :config command' do
        stub_updates([update(update_id: 110, chat: chat_id.to_i, text: '/config')], offset: 101)
        stub_updates([], offset: 111)

        expect(poller.commands).to eq [{ type: :config, args: [] }]
      end

      it 'returns an :add command with url and no config key' do
        stub_updates(
          [update(update_id: 110, chat: chat_id.to_i, text: '/add https://store.com/products/my-bike')],
          offset: 101
        )
        stub_updates([], offset: 111)

        expect(poller.commands).to eq [{ type: :add, args: ['https://store.com/products/my-bike'] }]
      end

      it 'returns an :add command with url and config key' do
        stub_updates(
          [update(update_id: 110, chat: chat_id.to_i, text: '/add https://store.com/products/my-bike my_watch')],
          offset: 101
        )
        stub_updates([], offset: 111)

        expect(poller.commands).to eq [{ type: :add, args: ['https://store.com/products/my-bike', 'my_watch'] }]
      end

      it 'acks after receiving updates' do
        stub_updates([update(update_id: 101, chat: chat_id.to_i, text: '/config')], offset: 101)
        ack = stub_updates([], offset: 102)

        poller.commands
        expect(ack).to have_been_requested
        expect(poller.last_update_id).to eq 101
      end

      it 'accepts /command@botname syntax' do
        stub_updates(
          [update(update_id: 110, chat: chat_id.to_i, text: '/config@shelf_monitor_bot')],
          offset: 101
        )
        stub_updates([], offset: 111)

        expect(poller.commands).to eq [{ type: :config, args: [] }]
      end

      it 'ignores commands from a different chat but still acks' do
        stub_updates([update(update_id: 150, chat: 999, text: '/config')], offset: 101)
        ack = stub_updates([], offset: 151)

        expect(poller.commands).to eq []
        expect(ack).to have_been_requested
      end

      it 'ignores unrecognized text' do
        stub_updates([update(update_id: 150, chat: chat_id.to_i, text: 'hello')], offset: 101)
        stub_updates([], offset: 151)

        expect(poller.commands).to eq []
      end

      it 'ignores unknown commands' do
        stub_updates([update(update_id: 150, chat: chat_id.to_i, text: '/disable')], offset: 101)
        stub_updates([], offset: 151)

        expect(poller.commands).to eq []
      end

      it 'returns multiple commands in order' do
        stub_updates(
          [
            update(update_id: 110, chat: chat_id.to_i, text: '/config'),
            update(update_id: 111, chat: chat_id.to_i, text: '/add https://store.com/products/bike-x')
          ],
          offset: 101
        )
        stub_updates([], offset: 112)

        expect(poller.commands).to eq [
          { type: :config, args: [] },
          { type: :add, args: ['https://store.com/products/bike-x'] }
        ]
      end
    end

    context 'on the first run (no baseline)' do
      subject(:poller) { described_class.new(since_update_id: nil) }

      it 'does not act on historical commands and establishes a baseline' do
        stub_updates([update(update_id: 42, chat: chat_id.to_i, text: '/config')])
        ack = stub_updates([], offset: 43)

        expect(poller.commands).to eq []
        expect(ack).to have_been_requested
        expect(poller.last_update_id).to eq 42
      end

      it 'leaves last_update_id nil when no updates are pending' do
        stub_updates([])

        poller.commands
        expect(poller.last_update_id).to be_nil
      end
    end

    it 'returns [] when the API call fails' do
      stub_request(:get, api_url)
        .with(query: { timeout: '0' })
        .to_return(status: 500, body: '')

      expect(described_class.new.commands).to eq []
    end
  end
end
