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

      def affected_records
        return affected_entries.collect(&:record).uniq
      end

      def affected_entries
        commits = Commit.containing(@staging_record)
        entries = commits.flat_map(&:related_commits).flat_map(&:entries)
        entries += CommitEntry.matching(@staging_record)
        return entries.uniq
      end

      private

      def record_exists_in_production?(staging_record)
        Production.exists?(staging_record)
      end

      def production_record(staging_record)
        Production.lookup(staging_record).first
      end
    end
  end
end
