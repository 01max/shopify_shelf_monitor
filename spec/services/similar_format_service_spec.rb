# frozen_string_literal: true

require 'spec_helper'
require_relative '../../services/similar_format_service'

RSpec.describe SimilarFormatService do
  describe '#call' do
    it 'formats entries into a Telegram message' do
      entries = [
        { product: { title: 'Air Max 90', handle: 'air-max-90', price: '150.00',
                     url: 'https://store.com/products/air-max-90' },
          similar: [
            { title: 'Air Max 95', handle: 'air-max-95', price: '180.00',
              url: 'https://store.com/products/air-max-95' },
            { title: 'Air Max 97', handle: 'air-max-97', price: '170.00',
              url: 'https://store.com/products/air-max-97' }

          ] }
      ]

      result = described_class.new('sneakers', entries).call

      expect(result).to include('*[sneakers]* similar products')
      expect(result).to include('Air Max 90')
      expect(result).to include('1. [Air Max 95](https://store.com/products/air-max-95)')
      expect(result).to include('2. [Air Max 97](https://store.com/products/air-max-97)')
    end

    it 'returns nil when no entries have similar products' do
      entries = [
        { product: { title: 'Air Max 90', handle: 'air-max-90', price: '150.00',
                     url: 'https://store.com/products/air-max-90' },
          similar: [] }
      ]

      result = described_class.new('sneakers', entries).call

      expect(result).to be_nil
    end

    it 'skips entries with no similar products' do
      entries = [
        { product: { title: 'Air Max 90', handle: 'air-max-90', price: '150.00',
                     url: 'https://store.com/products/air-max-90' },
          similar: [] },
        { product: { title: 'Air Force 1', handle: 'air-force-1', price: '100.00',
                     url: 'https://store.com/products/air-force-1' },
          similar: [{ title: 'Dunk Low', handle: 'dunk-low', price: '110.00',
                      url: 'https://store.com/products/dunk-low' }] }

      ]

      result = described_class.new('sneakers', entries).call

      expect(result).not_to include('Air Max 90')
      expect(result).to include('Air Force 1')
      expect(result).to include('Dunk Low')
    end
  end
end
