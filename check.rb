# frozen_string_literal: true

require 'json'
require 'logger'
require 'yaml'

require_relative 'services/product/watch_service'
require_relative 'services/collection/watch_service'
require_relative 'services/report_build_service'

unless ENV['CI']
  require 'dotenv'
  Dotenv.load
end

# @return [Logger]
def build_logger
  logger = Logger.new($stdout)
  logger.progname = 'shelf_monitor'
  logger
end

# @param logger [Logger]
# @return [Hash] parsed config.yml contents
def load_config(logger)
  config_path = File.expand_path('config.yml', __dir__)

  unless File.exist?(config_path)
    logger.error("config.yml not found at #{config_path}")
    exit 1
  end

  config = YAML.safe_load_file(config_path)

  if config.nil? || config.empty?
    logger.error('config.yml is empty or invalid')
    exit 1
  end

  config
end

# @param logger [Logger]
# @return [Hash{String => Hash}] previous watch results keyed by watch name, or empty hash
def load_previous_data(logger)
  previous_report_path = File.expand_path('tmp/report.json', __dir__)
  data = JSON.parse(File.read(previous_report_path))
  data['watches'].to_h { |w| [w['watch'], w] }
rescue StandardError
  logger.warn("Previous report not found or invalid at #{previous_report_path}, starting fresh")
  {}
end

# @param watch_name [String]
# @param params [Hash] watch config from config.yml
# @param logger [Logger]
# @param previous_data [Hash{String => Hash}]
# @return [Hash] watch result
def run_watch(watch_name, params, logger, previous_data)
  service_class = params['type'] == 'collection' ? Collection::WatchService : Product::WatchService
  previous_products = previous_data.dig(watch_name, 'products')
  service_class.new(watch_name, params, logger, previous_products).call
end

# @return [Boolean] true if all watches succeeded
def main
  logger = build_logger
  config = load_config(logger)
  previous_data = load_previous_data(logger)

  success = true
  results = []

  config.each do |watch_name, params|
    results << run_watch(watch_name, params, logger, previous_data)
  rescue StandardError => e
    logger.error("#{watch_name}: #{e.message}")
    results << { watch_name: watch_name, type: params['type'], error: e.message }
    success = false
  end

  ReportBuildService.new(results).call

  return success
end

exit(main ? 0 : 1)
