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

    context 'when another connection is writing to records being synced' do
      without_transactional_fixtures

      it 'does not sync the record if an outside write makes a change to the record during the sync' do
        # thread 1 initiates sync
        # thread 1 finds list of entries that are autosyncable
        # thread 2 modifies one of the records refered to in the list of entries
        # thread 1 attempts to sync each of the entries in the list

        # expect the changes to the modified record are not synced
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

    it 'does not sync records modified from within the block if they are the subject of an existing commit' do
      Stagehand::Staging::Commit.capture(source_record) { source_record.increment!(:counter) }
      expect { subject.sync_now { source_record.increment!(:counter) } }.not_to change { Stagehand::Production.status(source_record) }
    end

    it 'does sync records modified from within the block if they are the subject of an existing commit but that record is passed as the subject' do
      Stagehand::Staging::Commit.capture(source_record) { source_record.increment!(:counter) }
      expect { subject.sync_now(source_record) { source_record.increment!(:counter) } }.to change { Stagehand::Production.status(source_record) }
    end

    it 'does not sync changes to records not modified in the block' do
      other_record = SourceRecord.create
      expect { subject.sync_now { source_record.increment!(:counter) } }.not_to change { Stagehand::Production.status(other_record) }
    end

    context 'when multiple connections are modifying a record during the block' do
      without_transactional_fixtures

      let(:thread_1) do
        Thread.new do
          subject.sync_now do
            @thread_1_syncing = true
            sleep 0.1 until @thread_1_wake_before_write
            SourceRecord.find(source_record.id).update_columns(:counter => 1)
            @thread_1_done = true
            sleep 0.1 until @thread_1_wake_after_write
          end
        end
      end

      before do
        source_record
        @thread_1_syncing = false
        @thread_1_wake_before_write = false
        @thread_1_wake_after_write = false
        @thread_1_done = false
        thread_1
      end

      it 'syncs outside writes made before writes in the block' do
        sleep 0.1 until @thread_1_syncing

        thread_2 = Thread.new do
          SourceRecord.find(source_record.id).update_columns(:name => 'Bob')
          @thread_1_wake_before_write = true
          @thread_1_wake_after_write = true
        end

        thread_1.join(1) || fail('Timed out waiting for Thread 1')
        thread_2.join(1) || fail('Timed out waiting for Thread 2')

        expect(Stagehand::Production.find(source_record)).to have_attributes(:name => 'Bob')
      end

      it 'does not block external reads of records after they are written to in the block' do
        @thread_1_wake_before_write = true
        sleep 0.1 until @thread_1_done

        thread_2 = Thread.new do
          SourceRecord.find(source_record.id)
          @thread_1_wake_after_write = true
        end

        thread_1.join(1) || fail('Timed out waiting for Thread 1')
        thread_2.join(1) || fail('Timed out waiting for Thread 2')

        expect(Stagehand::Production.find(source_record)).not_to have_attributes(:name => 'Bob')
      end

      it 'does not sync outside writes made after writes in the block' do
        @thread_1_wake_before_write = true
        sleep 0.1 until @thread_1_done

        thread_2 = Thread.new do
          SourceRecord.find(source_record.id).update_columns(:name => 'Bob')
        end

        sleep 0.1 until thread_2.status == 'sleep' # NOTE: This condition assumes thread_2 only sleeps while waiting for the lock on source_record
        @thread_1_wake_after_write = true

        thread_1.join(1) || fail('Timed out waiting for Thread 1')
        thread_2.join(1) || fail('Timed out waiting for Thread 2')

        expect(Stagehand::Production.find(source_record)).not_to have_attributes(:name => 'Bob')
      end
    end
  end

  shared_examples_for 'sync callbacks' do
    class SyncCallbackMock < SourceRecord
      before_sync :before_sync_callback
      after_sync :after_sync_callback

      def before_sync_callback
        self.name = 'before'
        save!
      end

      def after_sync_callback
        self.name << 'after'
        save!
      end
    end

    let(:record) { SyncCallbackMock.create(:name => 'mock') }

    it 'runs :before_sync callback' do
      subject.sync_record(record)
      expect(record.reload.name).to include('before')
    end

    it 'runs :after_sync callback' do
      subject.sync_record(record)
      expect(record.reload.name).to include('after')
    end
  end

  context 'in a multi-database configuration' do
    it_behaves_like 'sync callbacks'
  end

  context 'in a single database configuration' do
    connection = Stagehand.configuration.staging_connection_name
    use_configuration(:staging_connection_name => connection, :production_connection_name => connection)

    it_behaves_like 'sync callbacks'
  end

  in_ghost_mode do
    it_behaves_like 'sync callbacks'
  end
end
