# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'logger'
require 'uri'
require 'yaml'

require_relative 'services/telegram/chat_service'
require_relative 'services/telegram/command_poller'

unless ENV['CI']
  require 'dotenv'
  Dotenv.load
end

PREVIOUS_STATE_PATH = File.expand_path('tmp/previous/command_state.json', __dir__)
STATE_PATH          = File.expand_path('tmp/command_state.json', __dir__)
CONFIG_PATH         = File.expand_path('config.yml', __dir__)

# @param url [String] Shopify product URL, e.g. "https://upway.fr/products/some-handle-rr3em8"
# @return [String, nil] product handle extracted from the URL path, or nil if invalid
def extract_handle(url)
  path = URI.parse(url).path
  segments = path.split('/').reject(&:empty?)
  return nil unless segments[-2] == 'products'

  segments.last
rescue URI::InvalidURIError
  nil
end

# Resolves which config key to add the handle to.
#
# @param config [Hash] parsed config.yml
# @param config_key [String, nil] explicit key supplied by the user, or nil to auto-detect
# @return [String, nil] resolved key, or nil on error (error already delivered via telegram)
def resolve_config_key(config, config_key, telegram)
  return resolve_explicit_key(config, config_key, telegram) if config_key

  auto_detect_key(config, telegram)
end

def resolve_explicit_key(config, config_key, telegram)
  return config_key if config[config_key]&.fetch('type', nil) == 'products'

  telegram.deliver("Unknown products key `#{config_key}`")
  nil
end

def auto_detect_key(config, telegram)
  keys = config.select { |_, v| v['type'] == 'products' }.keys
  return keys.first if keys.size == 1
  return notify_no_products_key(telegram) if keys.empty?

  notify_ambiguous_products_keys(keys, telegram)
end

def notify_no_products_key(telegram)
  telegram.deliver('No products watch found in config')
  nil
end

def notify_ambiguous_products_keys(keys, telegram)
  list = keys.map { |k| "`#{k}`" }.join(', ')
  telegram.deliver("Multiple products watches — pass the key as second argument.\nAvailable: #{list}")
  nil
end

# @param logger [Logger]
def build_logger
  logger = Logger.new($stdout)
  logger.progname = 'shelf-commands'
  logger
end

def handle_config(telegram)
  body = File.exist?(CONFIG_PATH) ? File.read(CONFIG_PATH) : '(config.yml not found)'
  telegram.deliver("Unfig:\n```\n#{body}\n```")
end

def handle_add(command, telegram, logger)
  url, config_key = command[:args]
  logger.info("/add received — url=#{url.inspect} key=#{config_key.inspect}")
  return telegram.deliver('Usage: /add <product_url> [config_key]') unless url

  handle = extract_handle(url)
  return telegram.deliver("Could not extract handle from `#{url}`\nExpected: `https://<store>/products/<handle>`") unless handle

  add_handle_to_config(handle, config_key, telegram, logger)
end

def add_handle_to_config(handle, config_key, telegram, logger)
  config = YAML.safe_load_file(CONFIG_PATH)
  key = resolve_config_key(config, config_key, telegram)
  return unless key

  handles = config[key]['handles'] ||= []
  return telegram.deliver("`#{handle}` is already in `#{key}`") if handles.include?(handle)

  handles << handle
  File.write(CONFIG_PATH, config.to_yaml)
  logger.info("Added #{handle} to #{key}")
  telegram.deliver("Added `#{handle}` to `#{key}`")
end

logger = build_logger

since_update_id = begin
  JSON.parse(File.read(PREVIOUS_STATE_PATH))['last_update_id']
rescue StandardError
  logger.warn("No previous command state at #{PREVIOUS_STATE_PATH} — processing all pending updates")
  nil
end || 0

poller = Telegram::CommandPoller.new(since_update_id: since_update_id)
commands = poller.commands
telegram = Telegram::ChatService.new

commands.each do |command|
  case command[:type]
  when :config
    logger.info('/config received — sending current config')
    handle_config(telegram)
  when :add
    handle_add(command, telegram, logger)
  end
end

FileUtils.mkdir_p(File.dirname(STATE_PATH))
File.write(STATE_PATH, JSON.pretty_generate(last_update_id: poller.last_update_id))
