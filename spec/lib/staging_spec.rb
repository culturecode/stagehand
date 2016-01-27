require 'rails_helper'

describe Stagehand::Staging do
  describe '::capture_saves' do
    let(:source_record) { SourceRecord.create }

    it 'outputs an array'
    it 'includes all records that were created'
    it 'includes all records that were updated'
    it 'includes all records that were destroyed'
    it 'does not include records modified outside of the block'
  end
end
