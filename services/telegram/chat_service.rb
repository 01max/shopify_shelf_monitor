# frozen_string_literal: true

require 'httparty'

module Telegram
  # Sends messages to a Telegram chat via the Bot API.
  #
  # Credentials are read from the environment variables +TELEGRAM_BOT_TOKEN+ and
  # +TELEGRAM_DEFAULT_CHAT_ID+. A per-watch +chat_id+ can be passed at construction
  # time to override the default.
  #
  # @example Send a plain message
  #   Telegram::ChatService.new.deliver("Hello!")
  #
  # @example Send a message with an inline button
  #   markup = Telegram::ChatService.build_inline_keyboard([{ text: 'Book', url: 'https://...' }])
  #   Telegram::ChatService.new.deliver("Slots found!", reply_markup: markup)
  class ChatService
    attr_reader :chat_id

    # @param chat_id [String] Telegram chat ID; defaults to +TELEGRAM_DEFAULT_CHAT_ID+
    def initialize(chat_id: ENV.fetch('TELEGRAM_DEFAULT_CHAT_ID'))
      @chat_id = chat_id
    end

    # Posts a message to the configured chat.
    #
    # @param text [String] message body (Markdown by default)
    # @param parse_mode [String] Telegram parse mode (+Markdown+ or +HTML+)
    # @param reply_markup [Hash, nil] inline keyboard markup built by {.build_inline_keyboard}
    # @return [void]
    def deliver(text, parse_mode: 'Markdown', reply_markup: nil)
      HTTParty.post(
        "https://api.telegram.org/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}/sendMessage",
        body: build_body(text, parse_mode, reply_markup)
      )
    end

    private

    # @param text [String]
    # @param parse_mode [String]
    # @param reply_markup [Hash, nil]
    # @return [Hash]
    def build_body(text, parse_mode, reply_markup)
      body = { chat_id: chat_id, text: text, parse_mode: parse_mode }
      body[:reply_markup] = reply_markup.to_json if reply_markup
      body
    end

    class << self
      # Builds an inline keyboard markup hash suitable for the Telegram Bot API.
      #
      # Accepts either a flat array of button hashes (rendered as a single row) or an
      # array of arrays (each inner array becomes one row).
      #
      # @param buttons [Array<Hash>, Array<Array<Hash>>] button definitions with +:text+ and +:url+
      # @return [Hash, nil] +{ inline_keyboard: [[...]] }+ or +nil+ if +buttons+ is empty
      def build_inline_keyboard(buttons)
        return nil if buttons.nil? || buttons.empty?

        keyboard = buttons.first.is_a?(Array) ? buttons : [buttons]
        { inline_keyboard: keyboard }
      end
    end
  end
end
