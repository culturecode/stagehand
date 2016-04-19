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
      commit = Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      subject.sync_record(source_record)

      expect(commit.entries.reload).to be_blank
    end

    it 'deletes all control entries for indirectly related commits' do
      other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter); other_record.increment!(:counter) }
      commit = Stagehand::Staging::Commit.capture { other_record.increment!(:counter) }
      subject.sync_record(source_record)

      expect(commit.entries.reload).to be_blank
    end

    it 'raises an exception if staging and production schemas are out of sync' do
      subject.schemas_match = nil
      Stagehand::Database.staging_connection.execute('INSERT INTO schema_migrations VALUES (1234)')
      expect { subject.sync_record(source_record) }.to raise_exception(Stagehand::SchemaMismatch)
      subject.schemas_match = nil
    end

    it 'does not deadlock when used in a transaction and staging and production databases are the same' do
      connection = Stagehand.configuration.staging_connection_name
      with_configuration(:staging_connection_name => connection, :production_connection_name => connection) do
        ActiveRecord::Base.transaction do
          expect { subject.sync_record(source_record) }.not_to raise_exception
        end
      end
    end
  end

  describe '::sync' do
    it 'syncs records with only entries that do not belong to a commit ' do
      source_record.increment!(:counter)
      expect { subject.sync }.to change { Stagehand::Production.status(source_record) }.to(:not_modified)
    end

    it 'does not sync records with entries that belong to a commit' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      expect { subject.sync }.not_to change { Stagehand::Production.status(source_record) }
    end

    it 'does not sync records with entries that belong to commits in progress' do
      start_operation = Stagehand::Staging::CommitEntry.start_operations.create
      source_record.increment!(:counter)
      expect { subject.sync }.not_to change { Stagehand::Production.status(source_record) }
    end

    it 'does not sync records with entries that belong to a commit and also entries that do not' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      source_record.increment!(:counter)
      expect { subject.sync }.not_to change { Stagehand::Production.status(source_record) }
    end

    it 'deletes records that have been updated and then deleted on staging' do
      Stagehand::Production.save(source_record)
      source_record.increment!(:counter)
      source_record.delete
      expect { subject.sync }.to change { Stagehand::Production.status(source_record) }.from(:modified).to(:new)
    end

    it 'deletes synced entries' do
      source_record
      commit_entry = Stagehand::Staging::CommitEntry.last
      subject.sync

      expect(commit_entry.class.where(:id => commit_entry)).not_to exist
    end

    it 'deletes stale entries' do
      source_record
      commit_entry = Stagehand::Staging::CommitEntry.last
      source_record.touch
      subject.sync

      expect(commit_entry.class.where(:id => commit_entry)).not_to exist
    end

    it 'stops syncing once the limit has been reached' do
      record_1 = SourceRecord.create
      record_2 = SourceRecord.create

      subject.sync(1)
      statuses = [record_1, record_2].collect {|record| Stagehand::Production.status(record) }

      expect(statuses.count(:not_modified)).to eq(1)
    end

    in_ghost_mode do
      it 'syncs records with only entries that do not belong to a commit ' do
        source_record.increment!(:counter)
        expect { subject.sync }.to change { Stagehand::Production.status(source_record) }.to(:not_modified)
      end

      it 'syncs records with entries that belong to a commit' do
        Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
        expect { subject.sync }.to change { Stagehand::Production.status(source_record) }.from(:new).to(:not_modified)
      end

      it 'syncs records with entries that belong to a commit and also entries that do not' do
        Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
        source_record.increment!(:counter)
        expect { subject.sync }.to change { Stagehand::Production.status(source_record) }.from(:new).to(:not_modified)
      end
    end
  end

  describe '::sync_all' do
    before { Stagehand::Production.save(source_record) }
    after { Stagehand::Production.delete(source_record) }

    it 'syncs records that require confirmation' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      expect{ subject.sync_all }.to change { Stagehand::Production.status(source_record) }.from(:modified).to(:not_modified)
    end

    it 'syncs records that do not require confirmation' do
      source_record.increment!(:counter)
      expect{ subject.sync_all }.to change { Stagehand::Production.status(source_record) }.from(:modified).to(:not_modified)
    end

    it 'does not attempt to sync a record twice if it has multiple entries' do
      source_record.increment!(:counter)
      expect(Stagehand::Production).to receive(:save).once
      subject.sync_all
    end

    it 'deletes records that have been modified and then deleted' do
      source_record.increment!(:counter)
      source_record.delete
      expect{ subject.sync_all }.to change { Stagehand::Production.status(source_record) }.from(:modified).to(:new)
    end

  end

  describe '::sync_now' do
    it 'requires a block' do
      expect { subject.sync_now }.to raise_exception(Stagehand::SyncBlockRequired)
    end

    it 'immediately syncs records modified from within the block if they are not part of an existing commit' do
      expect { subject.sync_now { source_record.increment!(:counter) } }
        .to change { Stagehand::Production.status(source_record) }.from(:new).to(:not_modified)
    end

    it 'does not sync records modified from within the block if they are part of an existing commit' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      expect { subject.sync_now { source_record.increment!(:counter) } }.not_to change { Stagehand::Production.status(source_record) }
    end

    it 'does not sync changes to records not modified in the block' do
      other_record = SourceRecord.create
      expect { subject.sync_now { source_record.increment!(:counter) } }.not_to change { Stagehand::Production.status(other_record) }
    end

    it 'does not sync changes to a record that are made outside the block while the block is executing'
  end
end
