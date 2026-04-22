# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../services/report_writer'

RSpec.describe ReportWriter do
  let(:tmpdir) { Dir.mktmpdir }
  let(:report_path) { File.join(tmpdir, 'report.json') }

  before do
    stub_const('ReportWriter::REPORT_PATH', report_path)
  end

  after do
    FileUtils.remove_entry(tmpdir)
  end

  describe '#call' do
    it 'creates the report file' do
      described_class.new([]).call

      expect(File.exist?(report_path)).to be true
    end

    it 'writes valid JSON' do
      described_class.new([]).call

      expect { JSON.parse(File.read(report_path)) }.not_to raise_error
    end

    it 'includes a generated_at timestamp' do
      described_class.new([]).call
      report = JSON.parse(File.read(report_path))

      expect(report).to have_key('generated_at')
      expect { Time.iso8601(report['generated_at']) }.not_to raise_error
    end

    it 'serializes a products watch result' do
      results = [{ watch_name: 'sneakers', type: 'products', status: 'ok',
                   products: [{ 'handle' => 'air-max-90' }] }]

      described_class.new(results).call
      report = JSON.parse(File.read(report_path))
      watch = report['watches'].first

      expect(watch['watch']).to eq('sneakers')
      expect(watch['type']).to eq('products')
      expect(watch['status']).to eq('ok')
      expect(watch['products']).to eq([{ 'handle' => 'air-max-90' }])
    end

    it 'serializes a collection watch result with products_count' do
      results = [{ watch_name: 'arrivals', type: 'collection', status: 'ok',
                   products: [{ 'handle' => 'shoe-a' }], products_count: 1 }]

      described_class.new(results).call
      report = JSON.parse(File.read(report_path))
      watch = report['watches'].first

      expect(watch['watch']).to eq('arrivals')
      expect(watch['type']).to eq('collection')
      expect(watch['products_count']).to eq(1)
      expect(watch['products']).to eq([{ 'handle' => 'shoe-a' }])
    end

    it 'serializes an error result' do
      results = [{ watch_name: 'broken', type: 'products', error: 'connection failed' }]

      described_class.new(results).call
      report = JSON.parse(File.read(report_path))
      watch = report['watches'].first

      expect(watch['watch']).to eq('broken')
      expect(watch['status']).to eq('error')
      expect(watch['error']).to eq('connection failed')
    end

    it 'creates the directory if it does not exist' do
      nested_path = File.join(tmpdir, 'nested', 'report.json')
      stub_const('ReportWriter::REPORT_PATH', nested_path)

      described_class.new([]).call

      expect(File.exist?(nested_path)).to be true
    end
  end
end
