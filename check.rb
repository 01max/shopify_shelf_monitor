# frozen_string_literal: true

require 'json'
require 'logger'
require 'yaml'

require_relative 'services/product_watch_service'
require_relative 'services/collection_watch_service'
require_relative 'services/report_build_service'

unless ENV['CI']
  require 'dotenv'
  Dotenv.load
end

logger = Logger.new($stdout)
logger.progname = 'shelf_monitor'

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

previous_report_path = File.expand_path('tmp/report.json', __dir__)
previous_data = begin
  data = JSON.parse(File.read(previous_report_path))
  data['watches'].to_h { |w| [w['watch'], w] }
rescue StandardError
  logger.warn("Previous report not found or invalid at #{previous_report_path}, starting fresh")
  {}
end

success = true
results = []

config.each do |watch_name, params|
  service_class = params['type'] == 'collection' ? CollectionWatchService : ProductWatchService
  previous_products = previous_data.dig(watch_name, 'products')

  results << service_class.new(watch_name, params, logger, previous_products).call
rescue StandardError => e
  logger.error("#{watch_name}: #{e.message}")
  results << { watch_name: watch_name, type: params['type'], error: e.message }
  success = false
end

ReportBuildService.new(results).call

exit(success ? 0 : 1)
