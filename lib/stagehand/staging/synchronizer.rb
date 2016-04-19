module Stagehand
  module Staging
    module Synchronizer
      extend self

      BATCH_SIZE = 1000

      # Immediately attempt to sync the changes from the block if possible
      # The block is wrapped in a transaction to prevent changes to records while being synced
      def sync_now(&block)
        raise SyncBlockRequired unless block_given?

        ActiveRecord::Base.transaction do
          checklist = Checklist.new(Commit.capture(&block).entries)
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

      private

      def sync_checklist(checklist)
        sync_entries(checklist.syncing_entries)
        CommitEntry.delete(checklist.affected_entries)
      end

      def sync_entries(entries)
        return 0 if Configuration.single_connection? # Avoid deadlocking if the databases are the same
        raise SchemaMismatch unless schemas_match?

        entries = Array.wrap(entries)

        ActiveRecord::Base.transaction do
          entries.each do |entry|
            Rails.logger.info "Synchronizing #{entry.table_name} #{entry.record_id}" if entry.content_operation?
            if entry.delete_operation?
              Stagehand::Production.delete(entry)
            elsif entry.save_operation?
              Stagehand::Production.save(entry)
            end
          end
        end

        return entries.length
      end

      # Lazily iterate through millions of commit entries
      # Returns commit entries in ID descending order
      def iterate_autosyncable_entries(&block)
        sessions = CommitEntry.order(:id => :desc).distinct.pluck(:session)
        offset = 0

        while sessions.present?
          autosyncable_entries(:session => sessions.shift(30)).offset(offset).limit(BATCH_SIZE).each(&block)
          offset += BATCH_SIZE
        end
      end

      # Returns commit entries in ID descending order
      def autosyncable_entries(scope = nil)
        entries = CommitEntry

        unless Configuration.ghost_mode?
          subquery = CommitEntry.content_operations.not_in_progress.group('record_id, table_name').having('count(commit_id) = 0').where(scope)
          entries = entries.joins("JOIN (#{subquery.select('MAX(id) AS max_id').to_sql}) subquery ON id = max_id")
        end

        return entries.order(:id => :desc)
      end

      def schemas_match?
        versions_scope = ActiveRecord::SchemaMigration.order(:version)
        staging_versions = Stagehand::Database.staging_connection.select_values(versions_scope)
        production_versions = Stagehand::Database.production_connection.select_values(versions_scope)
        return staging_versions == production_versions
      end
    end
  end

  # EXCEPTIONS

  class SyncBlockRequired < StandardError; end
  class SchemaMismatch < StandardError; end
end
