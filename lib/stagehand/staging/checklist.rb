module Stagehand
  module Staging
    class Checklist
      attr_reader :staging_record

      def initialize(staging_record, &confirmation_filter)
        @staging_record = staging_record
        @confirmation_filter = confirmation_filter
      end

      def confirm_create
        @confirm_create ||= compact_entries(requires_confirmation_entries).select(&:insert_operation?).collect(&:record)
      end

      def confirm_delete
        @confirm_delete ||= compact_entries(requires_confirmation_entries).select(&:delete_operation?).collect(&:record).compact
      end

      def confirm_update
        @confirm_update ||= compact_entries(requires_confirmation_entries).select(&:update_operation?).collect(&:record)
      end

      # Returns a list of records that exist in commits where the staging_record is not in the start operation
      def requires_confirmation
        @requires_confirmation ||= requires_confirmation_entries.collect(&:record).uniq
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
      def requires_confirmation_entries
        return @requires_confirmation_entries if @requires_confirmation_entries

        @requires_confirmation_entries = []
        affected_entries.group_by(&:commit_id).each do |commit_id, entries|
          next unless commit_id
          start_operation = entries.detect {|entry| entry.id == commit_id }
          @requires_confirmation_entries.concat(entries) if !start_operation || (start_operation.record != @staging_record)
        end

        @requires_confirmation_entries.select! {|entry| @confirmation_filter.call(entry.record) } if @confirmation_filter

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

      # Returns a list of entries that only includes a single entry for each record.
      # The type of entry chosen prioritizes creates over updates, and deletes over creates.
      def compact_entries(entries)
        return @compacted_entries if @compacted_entries

        @compacted_entries = entries.sort_by do |entry|
          if entry.delete_operation? then 0
          elsif entry.insert_operation? then 1
          elsif entry.update_operation? then 2
          else 3
          end
        end

        @compacted_entries.uniq!(&:key)

        return @compacted_entries
      end

    end
  end
end
