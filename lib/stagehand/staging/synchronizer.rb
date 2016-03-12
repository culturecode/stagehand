module Stagehand
  module Staging
    module Synchronizer
      def self.auto_sync(delay = nil)
        loop do
          sync_entries(CommitEntry.key_uncontained.order('id DESC').limit(1000))
          sleep(delay) if delay
        end
      end

      # Copies all the affected records from the staging database to the production database
      def self.sync_record(record)
        return Synchronizer.sync_entries(Checklist.new(record).compacted_entries)
      end

      def self.sync_entries(entries)
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
    end
  end
end
