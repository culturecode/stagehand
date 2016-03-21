require 'rails_helper'

describe Stagehand::Staging::Synchronizer do
  let(:source_record) { SourceRecord.create }

  describe '::sync_record' do
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

    it 'deletes all control entries for directly related commits' do
      commit = Stagehand::Staging::Commit.capture { source_record.touch }
      subject.sync_record(source_record)

      expect(commit.entries.reload).to be_blank
    end

    it 'deletes all control entries for indirectly related commits' do
      other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { source_record.touch; other_record.touch }
      commit = Stagehand::Staging::Commit.capture { other_record.touch }
      subject.sync_record(source_record)

      expect(commit.entries.reload).to be_blank
    end
  end

  describe '::sync' do
    it 'syncs records with only entries that do not belong to a commit ' do
      source_record.touch
      expect { subject.sync }.to change { Stagehand::Production.status(source_record) }.to(:not_modified)
    end

    it 'does not sync records with entries that belong to a commit' do
      Stagehand::Staging::Commit.capture { source_record.touch }
      expect { subject.sync }.not_to change { Stagehand::Production.status(source_record) }
    end

    it 'does not sync records with entries that belong to commits in progress' do
      start_operation = Stagehand::Staging::CommitEntry.start_operations.create
      source_record.touch
      expect { subject.sync }.not_to change { Stagehand::Production.status(source_record) }
    end

    it 'does not sync records with entries that belong to a commit and also entries that do not' do
      Stagehand::Staging::Commit.capture { source_record.touch }
      source_record.touch
      expect { subject.sync }.not_to change { Stagehand::Production.status(source_record) }
    end

    it 'deletes records that have been updated and then deleted on staging' do
      Stagehand::Production.save(source_record)
      source_record.touch
      source_record.delete
      expect { subject.sync }.to change { Stagehand::Production.status(source_record) }.from(:modified).to(:new)
    end
  end
end
