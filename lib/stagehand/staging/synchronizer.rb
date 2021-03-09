module Stagehand
  module Staging
    module Synchronizer
      extend self
      mattr_accessor :schemas_match

      BATCH_SIZE = 1000
      ENTRY_SYNC_ORDER = [:delete, :update, :insert].freeze
      ENTRY_SYNC_ORDER_SQL = Arel.sql(ActiveRecord::Base.send(:sanitize_sql_for_order, [Arel.sql('FIELD(operation, ?), id DESC'), ENTRY_SYNC_ORDER])).freeze

      # Immediately attempt to sync the changes from the block if possible
      # The block is wrapped in a transaction to prevent changes to records while being synced
      def sync_now(subject_record = nil, &block)
        raise SyncBlockRequired unless block_given?

        Rails.logger.info "Syncing Now"
        Database.transaction do
          commit = Commit.capture(subject_record, &block)
          next unless commit # If the commit was empty don't continue
          checklist = Checklist.new(commit.entries)
          sync_checklist(checklist) unless checklist.requires_confirmation?
        end
      end

      def auto_sync(polling_delay = 5.seconds)
        loop do
          Rails.logger.info "Autosyncing"
          sync(BATCH_SIZE)
          sleep(polling_delay) if polling_delay
        rescue Database::NoRetryError => e
          Rails.logger.info "Autosyncing encountered a NoRetryError"
        end
      end

      def sync(limit = nil)
        synced_count = 0
        deleted_count = 0

        Rails.logger.info "Syncing"

        iterate_autosyncable_entries do |entry|
          sync_entry(entry, :callbacks => :sync)
          synced_count += 1
          deleted_count += CommitEntry.matching(entry).no_newer_than(entry).delete_all
          break if synced_count == limit
        end

        Rails.logger.info "Synced #{synced_count} entries"
        Rails.logger.info "Removed #{deleted_count} stale entries"

        return synced_count
      end

      def sync_all
        loop do
          entries = CommitEntry.order(ENTRY_SYNC_ORDER_SQL).limit(BATCH_SIZE).to_a
          break unless entries.present?

          latest_entries = entries.uniq(&:key)
          latest_entries.each {|entry| sync_entry(entry, :callbacks => :sync) }
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
        Database.transaction do
          checklist.syncing_entries.each do |entry|
            if checklist.subject_entries.include?(entry)
              sync_entry(entry, :callbacks => [:sync, :sync_as_subject])
            else
              sync_entry(entry, :callbacks => [:sync, :sync_as_affected])
            end
          end

          CommitEntry.delete(checklist.affected_entries)
        end
      end

      private

      # Lazily iterate through millions of commit entries
      # Returns commit entries in ID descending order
      def iterate_autosyncable_entries(&block)
        current = CommitEntry.maximum(:id).to_i

        while entries = autosyncable_entries("id <= #{current}").limit(BATCH_SIZE).order(ENTRY_SYNC_ORDER_SQL).to_a.presence do
          with_confirmed_autosyncability(entries.uniq(&:key), &block)
          current = entries.last.try(:id).to_i - 1
        end
      end

      # Executes the code in the block if the record referred to by the entry is in fact, autosyncable.
      # This confirmation is used to guard against writes to the record that occur after loading an initial list of
      # entries that are autosyncable, but before the record is actually synced. To prevent this, a lock on the record
      # is acquired and then the record's autosync eligibility is rechecked before calling the block.
      def with_confirmed_autosyncability(entries, &block)
        entries = Array.wrap(entries)
        return unless entries.present?

        Database.transaction do
          # Lock the records so nothing can update them after we confirm autosyncability
          acquire_record_locks(entries)

          # Execute the block for each entry we've confirm autosyncability
          confirmed_ids = Set.new(autosyncable_entries.where(:id => entries).pluck(:id))

          entries.each do |entry|
            block.call(entry) if confirmed_ids.include?(entry.id)
          end
        end
      end

      # Does not actually acquire a lock, instead it triggers a 'first read' so the transaction will ensure subsequent
      # reads of the locked rows return the same value, even if modified outside of the transaction
      def acquire_record_locks(entries)
        entries.each(&:record)
      end

      def autosyncable_entries(scope = nil)
        entries = CommitEntry.content_operations.where(scope)
        entries = entries.with_uncontained_keys unless Configuration.ghost_mode?
        return entries
      end

      def sync_entry(entry, callbacks: [])
        raise SchemaMismatch unless schemas_match?

        run_sync_callbacks(entry, callbacks) do
          next unless entry.content_operation? # Only sync records from content operations because those are the only rows that have changes
          next if Configuration.single_connection? # Avoid deadlocking if the databases are the same. There is nothing to sync because there is only a single database

          Rails.logger.info "Synchronizing #{entry.table_name} #{entry.record_id} (#{entry.operation})"

          if entry.delete_operation?
            Production.delete(entry)
          elsif entry.save_operation?
            Production.save(entry)
          end

          Rails.logger.info "Synchronized #{entry.table_name} #{entry.record_id} (#{entry.operation})"
        end
      end

      def schemas_match?
        return schemas_match unless schemas_match.nil?
        self.schemas_match = Database.staging_database_versions == Database.production_database_versions
        return schemas_match
      end

      def run_sync_callbacks(entry, callbacks, &block)
        callbacks = Array.wrap(callbacks).dup
        return block.call unless callbacks.present? && entry.record

        entry.record.run_callbacks(callbacks.shift) do
          run_sync_callbacks(entry, callbacks, &block)
        end
      end
    end
  end

  # EXCEPTIONS

  class SyncBlockRequired < StandardError; end
  class SchemaMismatch < StandardError; end
end
