module Stagehand
  module Staging
    module Synchronizer
      extend self

      def auto_sync(delay = 5.seconds)
        scope = autosyncable_entries.limit(1000)

        loop do
          puts "Synced #{sync_entries(scope.reload)} entries"
          sleep(delay) if delay
        end
      end

      def sync_autosyncable
        sync_entries(autosyncable_entries.find_each)
      end

      def sync_all
        sync_entries(CommitEntry.find_each)
      end

      # Copies all the affected records from the staging database to the production database
      def sync_record(record)
        sync_entries(Checklist.new(record).compacted_entries)
      end

      private

      def sync_entries(entries)
        ActiveRecord::Base.transaction do
          max_id = 0
          entries.each do |entry|
            Rails.logger.info "Synchronizing #{entry.table_name} #{entry.record_id}"
            entry.delete_operation? ? Stagehand::Production.delete(entry) : Stagehand::Production.save(entry)
            max_id = entry.id if entry.id > max_id
          end
          # Delete any entries that match since we don't need to sync them now that we've copied their records
          # Don't delete any entries after the synced entries in case the record was updated after we synced it
          CommitEntry.matching(entries).where('id <= ?', max_id).delete_all
        end

        return entries.length
      end

      def autosyncable_entries
        Configuration.ghost_mode ? CommitEntry : CommitEntry.auto_syncable
      end
    end
  end
end
