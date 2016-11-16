module Stagehand
  module Staging
    class Checklist
      extend Cache
      include Cache

      def self.related_commits(commit)
        Commit.find(related_commit_ids(commit))
      end

      def self.related_commit_ids(commit)
        related_entries(commit.entries).collect(&:commit_id).select(&:present?).uniq
      end

      def self.related_entries(entries)
        entries = Array.wrap(entries)
        related_entries = []

        entries_to_spider = Array.wrap(entries)
        while entries_to_spider.present?
          contained_matching = CommitEntry.contained.matching(entries_to_spider)
          matching_commit_entries = CommitEntry.where(:commit_id => contained_matching.select(:commit_id))

          # Spider using content operations. Don't spider control operations to avoid extending the list of results unnecessarily
          content_operations, control_operations = matching_commit_entries.partition(&:content_operation?)
          entries_to_spider = content_operations - related_entries

          # Record the spidered entries and the control entries
          related_entries.concat(entries_to_spider)
          related_entries.concat(control_operations)
        end

        # Also include uncontained commit entries that matched
        related_entries.concat(CommitEntry.uncontained.matching(entries + related_entries))
        related_entries.uniq!

        return related_entries
      end

      def self.associated_records(entries)
        records = preload_records(compact_entries(entries)).select(&:record).flat_map do |entry|
          associated_associations(entry.record_class).flat_map do |association|
            entry.record.send(association)
          end
        end

        records.uniq!
        records.compact!
        records.select! {|record| stagehand_class?(record.class) }

        return records
      end

      # Returns a list of entries that only includes a single entry for each record.
      # The type of entry chosen prioritizes creates over updates, and deletes over creates.
      def self.compact_entries(entries)
        compact_entries = group_entries(entries)
        compact_entries = compact_entries[:delete] + compact_entries[:insert] + compact_entries[:update]
        compact_entries.uniq!(&:key)

        return compact_entries
      end

      # Groups entries by their operation
      def self.group_entries(entries)
        group_entries = Hash.new {|h,k| h[k] = [] }
        group_entries.merge! entries.group_by(&:operation).symbolize_keys!

        return group_entries
      end

      def self.preload_records(entries)
        entries.group_by(&:table_name).each do |table_name, group_entries|
          klass = CommitEntry.infer_class(table_name)
          records = klass.where(:id => group_entries.collect(&:record_id))
          records = records.includes(associated_associations(klass))
          records_by_id = records.collect {|r| [r.id, r] }.to_h
          group_entries.each do |entry|
            entry.record = records_by_id[entry.record_id]
          end
        end

        return entries
      end

      private

      def self.associated_associations(klass)
        cache("#{klass.name}_associated_associations") { klass.reflect_on_all_associations(:belongs_to).collect(&:name) }
      end

      def self.stagehand_class?(klass)
        cache("#{klass.name}_stagehand_class?") { Schema.has_stagehand?(klass.table_name) }
      end

      public

      def initialize(subject, &confirmation_filter)
        @subject = subject
        @confirmation_filter = confirmation_filter
        affected_entries # Init the affected_entries changes can be rolled back without affecting the checklist
      end

      def confirm_create
        cache(:confirm_create) { grouped_required_confirmation_entries[:insert].collect(&:record) }
      end

      def confirm_delete
        cache(:confirm_delete) { grouped_required_confirmation_entries[:delete].collect(&:record).compact }
      end

      def confirm_update
        cache(:confirm_update) { grouped_required_confirmation_entries[:update].collect(&:record) }
      end

      # Returns true if there are any changes in the checklist that require confirmation
      def requires_confirmation?
        cache(:requires_confirmation?) { grouped_required_confirmation_entries.values.flatten.present? }
      end

      # Returns a list of records that exist in commits where the staging_record is not in the start operation
      def requires_confirmation
        cache(:requires_confirmation) { grouped_required_confirmation_entries.values.flatten.collect(&:record).compact }
      end

      def syncing_entries
        cache(:syncing_entries) { self.class.compact_entries(affected_entries) }
      end

      def affected_records
        cache(:affected_records) { affected_entries.uniq(&:key).collect(&:record).compact }
      end

      def affected_entries
        cache(:affected_entries) do
          related = self.class.related_entries(@subject)
          associated = self.class.associated_records(related)
          associated_related = self.class.related_entries(associated)

          (related + associated_related).uniq
        end
      end

      private

      def grouped_required_confirmation_entries
        cache(:grouped_required_confirmation_entries) do
          entries = affected_entries.dup
          subject_entries, subject_records = Array.wrap(@subject).partition {|model| model.is_a?(CommitEntry) }

          # Don't need to confirm entries that were not part of a commit
          entries.select!(&:commit_id)

          # Don't need to confirm entries that exactly match a subject commit entry
          entries -= subject_entries

          # Don't need to confirm entries that match the checklist subject records
          entries.reject! {|entry| entry.matches?(subject_records) }

          # Don't need to confirm entries that are part of a commits whose subject is a checklist subject record
          staging_record_start_operation_ids = affected_entries.select do |entry|
            entry.start_operation? && entry.matches?(subject_records)
          end.collect(&:id)
          entries.reject! {|entry| staging_record_start_operation_ids.include?(entry.commit_id) }

          entries = self.class.compact_entries(entries)
          entries = filter_entries(entries)
          entries = self.class.group_entries(entries)
        end
      end

      def filter_entries(entries)
        return entries unless @confirmation_filter
        return entries.select {|entry| @confirmation_filter.call(entry.record) if entry.record }
      end
    end
  end
end
