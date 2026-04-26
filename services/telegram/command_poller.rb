# frozen_string_literal: true

require 'httparty'
require 'json'

module Telegram
  # Polls the Telegram Bot API for pending updates and detects control commands
  # sent from the authorized chat.
  #
  # The GitHub Actions cron has no long-lived process, so we use +getUpdates+ (long
  # polling disabled) at the start of each run rather than webhooks. After reading
  # updates, we acknowledge them by calling +getUpdates+ again with
  # +offset = last_update_id + 1+ so the same commands are not replayed on the
  # next run.
  class CommandPoller
    COMMANDS = { '/add' => :add, '/config' => :config }.freeze

    attr_reader :last_update_id

    # @param authorized_chat_id [String] only messages from this chat trigger commands
    # @param since_update_id [Integer, nil] the highest +update_id+ seen on the previous run;
    #   only messages strictly after this id are considered. When +nil+, the poller establishes
    #   a baseline by acknowledging any pending updates without acting on them — this prevents
    #   stale messages (sent before this feature was deployed) from triggering commands.
    def initialize(authorized_chat_id: ENV.fetch('TELEGRAM_DEFAULT_CHAT_ID'), since_update_id: nil)
      @authorized_chat_id = authorized_chat_id.to_s
      @since_update_id = since_update_id
      @last_update_id = since_update_id
    end

    # @return [Array<Hash>] commands received since the baseline, in the order they were seen.
    #   Each hash has a +:type+ key (Symbol) and an +:args+ key (Array<String>).
    #   Returns +[]+ on the first run so stale messages don't trigger actions.
    def commands
      updates = fetch_updates
      return [] if updates.empty?

      @last_update_id = updates.last['update_id']
      ack(@last_update_id)

      return [] if @since_update_id.nil?

      updates.filter_map { |u| detect_command(u) }
    end

    private

    # @return [Array<Hash>] raw Telegram update objects, or +[]+ on failure
    def fetch_updates
      query = { timeout: 0 }
      query[:offset] = @since_update_id + 1 if @since_update_id

      response = HTTParty.get(api_url('getUpdates'), query: query)
      return [] unless response.success?

      body = JSON.parse(response.body)
      Array(body['result'])
    rescue JSON::ParserError
      []
    end

    # Advances the bot's read cursor so processed updates are not replayed.
    # @param last_update_id [Integer]
    # @return [void]
    def ack(last_update_id)
      HTTParty.get(api_url('getUpdates'), query: { offset: last_update_id + 1, timeout: 0 })
    end

    # @param update [Hash] raw Telegram update object
    # @return [Hash, nil] command hash with +:type+ and +:args+, or +nil+ if not a recognized command
    def detect_command(update)
      message = update['message'] || update['channel_post']
      return nil unless message
      return nil unless message.dig('chat', 'id').to_s == @authorized_chat_id

      text = message['text'].to_s.strip
      parts = text.split(/\s+/)
      keyword = parts.first.to_s.downcase.split('@', 2).first
      command_type = COMMANDS[keyword]
      return nil unless command_type

      { type: command_type, args: parts[1..] }
    end

    # @param method [String] Telegram Bot API method name (e.g. +"getUpdates"+)
    # @return [String] full API URL for the method
    def api_url(method)
      "https://api.telegram.org/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}/#{method}"
    end
  end
end
