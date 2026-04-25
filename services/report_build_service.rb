# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

# Writes a JSON report to a file for later consumption.
class ReportBuildService
  REPORT_PATH = File.expand_path('../tmp/report.json', __dir__)

  # @param results [Array<Hash>] collected return values from watch services
  # @param path [String] destination file path (defaults to {REPORT_PATH})
  def initialize(results, path: REPORT_PATH)
    @results = results
    @path = path
  end

  # Serializes +results+ to the configured path as pretty-printed JSON.
  # Creates the parent directory if it does not exist.
  #
  # @return [void]
  def call
    FileUtils.mkdir_p(File.dirname(@path))

    report = {
      generated_at: Time.now.utc.iso8601,
      watches: @results.map { |r| serialize(r) }
    }

    File.write(@path, JSON.pretty_generate(report))
  end

  private

  # Converts a single watch result hash into its JSON-serializable form.
  #
  # @param result [Hash]
  # @return [Hash]
  def serialize(result)
    if result[:error]
      { watch: result[:watch_name], type: result[:type], status: 'error', error: result[:error] }
    elsif result[:type] == 'collection'
      { watch: result[:watch_name], type: 'collection', status: 'ok',
        products_count: result[:products_count], products: result[:products] }
    else
      { watch: result[:watch_name], type: 'products', status: 'ok', products: result[:products] }
    end
  end
end
