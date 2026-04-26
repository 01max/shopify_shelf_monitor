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
  if config_key
    entry = config[config_key]
    unless entry && entry['type'] == 'products'
      telegram.deliver("Unknown products key `#{config_key}`")
      return nil
    end

    return config_key
  end

  products_keys = config.select { |_, v| v['type'] == 'products' }.keys
  case products_keys.size
  when 1 then products_keys.first
  when 0
    telegram.deliver('No products watch found in config')
    nil
  else
    telegram.deliver(
      "Multiple products watches — pass the key as second argument.\n" \
      "Available: #{products_keys.map { |k| "`#{k}`" }.join(', ')}"
    )
    nil
  end
end

# @param logger [Logger]
def build_logger
  logger = Logger.new($stdout)
  logger.progname = 'shelf-commands'
  logger
end

logger = build_logger

since_update_id = begin
  JSON.parse(File.read(PREVIOUS_STATE_PATH))['last_update_id']
rescue StandardError
  logger.warn("No previous command state at #{PREVIOUS_STATE_PATH} — processing all pending updates")
  nil
end || 0

poller  = Telegram::CommandPoller.new(since_update_id: since_update_id)
commands = poller.commands
telegram = Telegram::ChatService.new

commands.each do |command|
  case command[:type]
  when :config
    logger.info('/config received — sending current config')
    body = File.exist?(CONFIG_PATH) ? File.read(CONFIG_PATH) : '(config.yml not found)'
    telegram.deliver("Unfig:\n```\n#{body}\n```")

  when :add
    url, config_key = command[:args]
    logger.info("/add received — url=#{url.inspect} key=#{config_key.inspect}")

    unless url
      telegram.deliver('Usage: /add <product_url> [config_key]')
      next
    end

    handle = extract_handle(url)
    unless handle
      telegram.deliver(
        "Could not extract handle from `#{url}`\n" \
        'Expected: `https://<store>/products/<handle>`'
      )
      next
    end

    config = YAML.safe_load_file(CONFIG_PATH)
    key = resolve_config_key(config, config_key, telegram)
    next unless key

    handles = config[key]['handles'] ||= []
    if handles.include?(handle)
      telegram.deliver("#{handle}` is already in `#{key}`")
      next
    end

    handles << handle
    File.write(CONFIG_PATH, config.to_yaml)
    logger.info("Added #{handle} to #{key}")
    telegram.deliver("Added `#{handle}` to `#{key}`")
  end
end

FileUtils.mkdir_p(File.dirname(STATE_PATH))
File.write(STATE_PATH, JSON.pretty_generate(last_update_id: poller.last_update_id))
