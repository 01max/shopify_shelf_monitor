# frozen_string_literal: true

require 'json'
require 'logger'
require 'yaml'

require_relative 'services/product/watch_service'
require_relative 'services/product/similar_service'
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
# @param message [String]
def abort_with(logger, message)
  logger.error(message)
  exit 1
end

# @param logger [Logger]
# @return [Hash] parsed config.yml contents
def load_config(logger)
  config_path = File.expand_path('config.yml', __dir__)
  abort_with(logger, "config.yml not found at #{config_path}") unless File.exist?(config_path)
  config = YAML.safe_load_file(config_path)
  abort_with(logger, 'config.yml is empty or invalid') if config.nil? || config.empty?
  config
end

# @return [String] report filename based on CHECK_TYPE env var
def report_path
  suffix = ENV.fetch('CHECK_TYPE', nil)
  name = suffix ? "report-#{suffix}.json" : 'report.json'
  File.expand_path("tmp/#{name}", __dir__)
end

# @param logger [Logger]
# @return [Hash{String => Hash}] previous watch results keyed by watch name, or empty hash
def load_previous_data(logger)
  path = report_path
  data = JSON.parse(File.read(path))
  data['watches'].to_h { |w| [w['watch'], w] }
rescue StandardError
  logger.warn("Previous report not found or invalid at #{path}, starting fresh")
  {}
end

# @param check_type [String, nil]
# @param watch_name [String]
# @param params [Hash] watch config from config.yml
# @param logger [Logger]
# @param previous_data [Hash{String => Hash}]
# @return [Hash] watch result
def run_watch(check_type, watch_name, params, logger, previous_data)
  return Product::SimilarService.new(watch_name, params, logger).call if check_type == 'similar'

  service_class = params['type'] == 'collection' ? Collection::WatchService : Product::WatchService
  previous_products = previous_data.dig(watch_name, 'products')
  service_class.new(watch_name, params, logger, previous_products).call
end

# @param config [Hash]
# @param check_type [String, nil] optional type filter (e.g. "products", "collection", "similar")
# @return [Hash] filtered config entries matching check_type, or all if nil
def filter_config(config, check_type)
  return config unless check_type

  # "similar" operates on "products" watches
  target_type = check_type == 'similar' ? 'products' : check_type
  config.select { |_, params| params['type'] == target_type }
end

# @return [Array<(Array<Hash>, Boolean)>] results array and success flag
def run_all_watches(config, logger, previous_data)
  check_type = ENV.fetch('CHECK_TYPE', nil)
  success = true
  results = filter_config(config, check_type).map do |watch_name, params|
    run_watch(check_type, watch_name, params, logger, previous_data)
  rescue StandardError => e
    logger.error("#{watch_name}: #{e.message}")
    success = false
    { watch_name: watch_name, type: params['type'], error: e.message }
  end
  [results, success]
end

# @return [Boolean] true if all watches succeeded
def main
  logger = build_logger
  config = load_config(logger)
  previous_data = load_previous_data(logger)
  results, success = run_all_watches(config, logger, previous_data)
  ReportBuildService.new(results, path: report_path).call unless ENV.fetch('CHECK_TYPE', nil) == 'similar'
  success
end

exit(main ? 0 : 1)
