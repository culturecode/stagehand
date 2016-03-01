module Stagehand
  module Staging
    class Checklist
      attr_reader :staging_record

      def initialize(staging_record, &confirmation_filter)
        @staging_record = staging_record
        @confirmation_filter = confirmation_filter
      end

      def confirm_create
        @confirm_create ||= grouped_required_confirmation_entries[:insert].collect(&:record)
      end

      def confirm_delete
        @confirm_delete ||= grouped_required_confirmation_entries[:delete].collect(&:record).compact
      end

      def confirm_update
        @confirm_update ||= grouped_required_confirmation_entries[:update].collect(&:record)
      end

      # Returns a list of records that exist in commits where the staging_record is not in the start operation
      def requires_confirmation
        @requires_confirmation ||= grouped_required_confirmation_entries.values.flatten.collect(&:record).compact
      end

      def affected_records
        @affected_records ||= affected_entries.collect(&:record).uniq
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

      # Returns entries that appear in commits where the starting_operation record is not this list's staging_record
      def grouped_required_confirmation_entries
        return @requires_confirmation_entries if @requires_confirmation_entries

        @requires_confirmation_entries = []
        affected_entries.group_by(&:commit_id).each do |commit_id, entries|
          next unless commit_id
          start_operation = entries.detect {|entry| entry.id == commit_id }
          @requires_confirmation_entries.concat(entries) if !start_operation || (start_operation.record != @staging_record)
        end

        @requires_confirmation_entries = filter_entries(@requires_confirmation_entries)
        @requires_confirmation_entries = compact_entries(@requires_confirmation_entries)
        @requires_confirmation_entries = group_entries(@requires_confirmation_entries)

        return @requires_confirmation_entries
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

      def filter_entries(entries)
        @confirmation_filter ? entries.select {|entry| @confirmation_filter.call(entry.record) } : entries
      end

      # Returns a list of entries that only includes a single entry for each record.
      # The type of entry chosen prioritizes creates over updates, and deletes over creates.
      def compact_entries(entries)
        compact_entries = group_entries(entries)
        compact_entries = compact_entries[:delete] + compact_entries[:insert] + compact_entries[:update]
        compact_entries.uniq!(&:key)

        return compact_entries
      end

      # Groups entries by their operation
      def group_entries(entries)
        group_entries = Hash.new {|h,k| h[k] = [] }
        group_entries.merge! entries.group_by(&:operation).symbolize_keys!

        return group_entries
      end
    end
  end
end
