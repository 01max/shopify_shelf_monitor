# frozen_string_literal: true

require 'spec_helper'
require_relative '../../services/debug_notifier'

RSpec.describe DebugNotifier do
  let(:output_path) { DebugNotifier::OUTPUT_PATH }

  before { FileUtils.rm_f(output_path) }

  after { FileUtils.rm_f(output_path) }

  describe '#deliver' do
    it 'appends a timestamped message line to the output file' do
      described_class.new.deliver('hello world')

      content = File.read(output_path)
      expect(content).to match(/\[MESSAGE\] hello world/)
    end

    it 'appends multiple messages' do
      notifier = described_class.new
      notifier.deliver('first')
      notifier.deliver('second')

      lines = File.readlines(output_path)
      expect(lines.size).to eq(2)
      expect(lines[0]).to include('[MESSAGE] first')
      expect(lines[1]).to include('[MESSAGE] second')
    end
  end

  describe '#send_media_group' do
    it 'appends a photo line for each URL' do
      described_class.new.send_media_group(%w[https://img1.jpg https://img2.jpg])

      lines = File.readlines(output_path)
      expect(lines.size).to eq(2)
      expect(lines[0]).to include('[PHOTO] https://img1.jpg')
      expect(lines[1]).to include('[PHOTO] https://img2.jpg')
    end
  end
end
