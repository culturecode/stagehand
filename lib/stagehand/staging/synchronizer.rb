module Stagehand
  module Staging
    module Synchronizer
      extend self

      # Immediately attempt to sync the changes from the block if possible
      # The block is wrapped in a transaction to prevent changes to records while being synced
      def sync_now(&block)
        ActiveRecord::Base.transaction do
          checklist = Checklist.new(Commit.capture(&block).entries)
          sync_checklist(checklist) unless checklist.requires_confirmation?
        end
      end

      def auto_sync(delay = 5.seconds)
        scope = autosyncable_entries.limit(1000)

        loop do
          puts "Synced #{sync_entries(scope.reload)} entries"
          sleep(delay) if delay
        end
      end

      def sync
        sync_entries(autosyncable_entries.limit(1000))
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
        if Configuration.ghost_mode?
          CommitEntry
        else
          CommitEntry.where(:id =>
            CommitEntry.select('MAX(id) AS id').content_operations.not_in_progress.group('record_id, table_name').having('count(commit_id) = 0'))
        end
      end
    end
  end
end
