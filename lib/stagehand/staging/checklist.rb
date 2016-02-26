module Stagehand
  module Staging
    class Checklist
      def initialize(staging_record)
        @staging_record = staging_record
      end

      def will_create
        affected_entries.reject(&:delete_operation?).collect(&:record).reject {|record| record_exists_in_production?(record) if record }
      end

      def will_delete
        affected_entries.select(&:delete_operation?).collect(&:record)
      end

      def can_update
        affected_entries.select(&:update_operation?).collect(&:record).select {|record| record.attributes != production_record(record).attributes }
      end

      # Returns a list of records that exist in commits where the staging_record is not in the start operation
      def requires_confirmation
        return @requires_confirmation if @requires_confirmation

        @requires_confirmation = []
        affected_entries.group_by(&:commit_id).each do |commit_id, entries|
          next unless commit_id
          start_operation = entries.detect {|entry| entry.id == commit_id }
          @requires_confirmation.concat entries.collect(&:record) if !start_operation || (start_operation.record != @staging_record)
        end

        @requires_confirmation.uniq!

        return @requires_confirmation
      end

      def affected_records
        @affected_records ||= affected_entries.collect(&:record).uniq
      end

      def affected_entries
        return @affected_entries if @affected_entries

        @affected_entries = []
        @affected_entries += CommitEntry.uncontained.matching(@staging_record)
        if commit = first_commit_containing_record(@staging_record)
          @affected_entries += commit.content_entries
          @affected_entries += commit.related_entries
        end

        return @affected_entries
      end

      private

      def record_exists_in_production?(staging_record)
        Production.exists?(staging_record)
      end

      def production_record(staging_record)
        Production.lookup(staging_record).first
      end

      def first_commit_containing_record(staging_record)
        Commit.find(CommitEntry.contained.matching(staging_record).limit(1).pluck(:commit_id).first)
      end
    end
  end
end
