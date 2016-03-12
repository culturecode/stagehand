require 'rails_helper'

describe Stagehand::Staging::Synchronizer do
  let(:source_record) { SourceRecord.create }

  describe '#sync_record' do
    it 'copies new records to the production database' do
      expect { subject.sync_record(source_record) }.to change { Stagehand::Production.status(source_record) }.to(:not_modified)
    end

    it 'updates existing records in the production database' do
      Stagehand::Production.save(source_record)
      source_record.update_attribute(:updated_at, 10.days.from_now)

      expect { subject.sync_record(source_record) }.to change { Stagehand::Production.status(source_record) }.to(:not_modified)
    end

    it 'deletes deleted records in the production database' do
      Stagehand::Production.save(source_record)
      source_record.destroy
      expect { subject.sync_record(source_record) }.to change { Stagehand::Production.status(source_record) }.to(:new)
    end

    it 'returns the number of records synchronized' do
      Stagehand::Production.save(source_record)
      expect(subject.sync_record(source_record)).to eq(1)
    end
  end
end
