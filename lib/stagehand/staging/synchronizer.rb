module Stagehand
  module Staging
    module Synchronizer
      extend self
      mattr_accessor :schemas_match

      BATCH_SIZE = 1000

      # Immediately attempt to sync the changes from the block if possible
      # The block is wrapped in a transaction to prevent changes to records while being synced
      def sync_now(&block)
        raise SyncBlockRequired unless block_given?

        ActiveRecord::Base.transaction do
          checklist = Checklist.new(Commit.capture(&block).entries, :preconfirm_subject => false)
          sync_checklist(checklist) unless checklist.requires_confirmation?
        end
      end

      def auto_sync(polling_delay = 5.seconds)
        loop do
          sync(BATCH_SIZE)
          sleep(polling_delay) if polling_delay
        end
      end

      def sync(limit = nil)
        synced_count = 0
        deleted_count = 0

        iterate_autosyncable_entries do |entry|
          sync_entries(entry)
          synced_count += 1
          deleted_count += CommitEntry.matching(entry).delete_all
          break if synced_count == limit
        end

        Rails.logger.info "Synced #{synced_count} entries"
        Rails.logger.info "Removed #{deleted_count} stale entries"

        return synced_count
      end

      def sync_all
        loop do
          entries = CommitEntry.order(:id => :desc).limit(BATCH_SIZE).to_a
          break unless entries.present?

          latest_entries = entries.uniq(&:key)
          sync_entries(latest_entries)
          Rails.logger.info "Synced #{latest_entries.count} entries"

          deleted_count = CommitEntry.matching(latest_entries).delete_all
          Rails.logger.info "Removed #{deleted_count - latest_entries.count} stale entries"
        end
      end

      # Copies all the affected records from the staging database to the production database
      def sync_record(record)
        sync_checklist(Checklist.new(record))
      end

      def sync_checklist(checklist)
        ActiveRecord::Base.transaction do
          sync_entries(checklist.syncing_entries)
          CommitEntry.delete(checklist.affected_entries)
        end
      end

      private

      # Lazily iterate through millions of commit entries
      # Returns commit entries in ID descending order
      def iterate_autosyncable_entries(&block)
        sessions = CommitEntry.order(:id => :desc).distinct.pluck(:session)
        offset = 0

        while sessions.present?
          autosyncable_entries(:session => sessions.shift(30)).offset(offset).limit(BATCH_SIZE).uniq(&:id).each do |entry|
            with_confirmed_autosyncability(entry, &block)
          end
          offset += BATCH_SIZE
        end
      end

      # Executes the code in the block if the record referred to by the entry is in fact, autosyncable.
      # This confirmation is used to guard against writes to the record that occur after loading an initial list of
      # entries that are autosyncable, but before the record is actually synced. To prevent this, a lock on the record
      # is acquired and then the record's autosync eligibility is rechecked before calling the block.
      # NOTE: This method must be called from within a transaction
      def with_confirmed_autosyncability(entry, &block)
        ActiveRecord::Base.transaction do
          CommitEntry.connection.execute("SELECT 1 FROM #{entry.table_name} WHERE id = #{entry.record_id}")
          block.call(entry) if autosyncable_entries(:record_id => entry.record_id, :table_name => entry.table_name).exists?
        end
      end

      def autosyncable_entries(scope = nil)
        entries = CommitEntry.content_operations.not_in_progress.where(scope).order(:id => :desc)
        entries = entries.with_uncontained_keys unless Configuration.ghost_mode?
        return entries
      end

      def sync_entries(entries)
        raise SchemaMismatch unless schemas_match?

        entries = Array.wrap(entries)

        entries.each do |entry|
          run_sync_callbacks(entry) do
            Rails.logger.info "Synchronizing #{entry.table_name} #{entry.record_id}" if entry.content_operation?
            if Configuration.single_connection?
              next # Avoid deadlocking if the databases are the same
            elsif entry.delete_operation?
              Stagehand::Production.delete(entry)
            elsif entry.save_operation?
              Stagehand::Production.save(entry)
            end
          end
        end

        return entries.length
      end

      def schemas_match?
        return schemas_match unless schemas_match.nil?
        self.schemas_match = Database.staging_database_versions == Database.production_database_versions
        return schemas_match
      end

      def run_sync_callbacks(entry, &block)
        entry.record.run_callbacks(:sync, &block) if entry.record
      end
    end
  end

  # EXCEPTIONS

  class SyncBlockRequired < StandardError; end
  class SchemaMismatch < StandardError; end
end
