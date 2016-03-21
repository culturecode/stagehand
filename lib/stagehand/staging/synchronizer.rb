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
        autosyncable_entries.find_in_batches do |entries|
          sync_entries(entries)

          # Delete any entries that match since we don't need to sync them now that we've copied their records
          # Don't delete any entries after the synced entries in case the record was updated after we synced it
          CommitEntry.matching(entries).where('id <= ?', entries.collect(&:id).max).delete_all
        end
      end

      # Copies all the affected records from the staging database to the production database
      def sync_record(record)
        checklist = Checklist.new(record)
        sync_entries(checklist.compacted_entries)
        CommitEntry.delete(checklist.affected_entries)
      end

      private

      def sync_entries(entries)
        ActiveRecord::Base.transaction do
          entries.each do |entry|
            Rails.logger.info "Synchronizing #{entry.table_name} #{entry.record_id}"
            if entry.delete_operation?
              Stagehand::Production.delete(entry)
            elsif entry.save_operation?
              Stagehand::Production.save(entry)
            end
          end
        end

        return entries.length
      end

      def autosyncable_entries
        Configuration.ghost_mode ? CommitEntry : CommitEntry.auto_syncable
      end
    end
  end
end
