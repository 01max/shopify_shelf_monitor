# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

# Writes a JSON report to a file for later consumption.
module ReportWriter
  REPORT_PATH = File.expand_path('../tmp/report.json', __dir__)

  # Serializes +results+ to {REPORT_PATH} as pretty-printed JSON.
  # Creates +tmp/+ if it does not exist.
  #
  # @param results [Array<Hash>] collected return values from watch services
  # @return [void]
  def self.write(results)
    FileUtils.mkdir_p(File.dirname(REPORT_PATH))

    report = {
      generated_at: Time.now.utc.iso8601,
      watches: results.map { |r| serialize(r) }
    }

    File.write(REPORT_PATH, JSON.pretty_generate(report))
  end

  # Converts a single watch result hash into its JSON-serializable form.
  #
  # @param result [Hash]
  # @return [Hash]
  def self.serialize(result)
    if result[:error]
      { watch: result[:watch_name], type: result[:type], status: 'error', error: result[:error] }
    elsif result[:type] == 'collection'
      { watch: result[:watch_name], type: 'collection', status: 'ok',
        products_count: result[:products_count], products: result[:products] }
    else
      { watch: result[:watch_name], type: 'products', status: 'ok', products: result[:products] }
    end
  end
  private_class_method :serialize
end
