# frozen_string_literal: true

require_relative 'telegram/chat_service'
require_relative 'debug_notifier'

# Factory that returns either a +Telegram::ChatService+ or a +DebugNotifier+,
# depending on the +DEBUG+ environment variable.
module Notifier
  def self.build(**chat_params)
    if ENV['DEBUG']
      DebugNotifier.new(**chat_params)
    else
      Telegram::ChatService.new(**chat_params)
    end
  end
end
