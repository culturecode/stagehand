module Stagehand
  module Staging
    class Checklist

      def self.related_commits(commit)
        Commit.find(related_commit_ids(commit))
      end

      def self.related_commit_ids(commit)
        related_entries(commit.entries).collect(&:commit_id).uniq
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

      def initialize(subject, &confirmation_filter)
        @subject = subject
        @confirmation_filter = confirmation_filter
        @cache = {}
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
        cache(:syncing_entries) { compact_entries(affected_entries) }
      end

      def affected_records
        cache(:affected_records) { affected_entries.collect(&:record).uniq }
      end

      def affected_entries
        cache(:affected_entries) { self.class.related_entries(@subject) }
      end

      private

      def grouped_required_confirmation_entries
        cache(:grouped_required_confirmation_entries) do
          staging_record_start_operation_ids = affected_entries.select do |entry|
            entry.start_operation? && entry.record_id? && entry.matches?(@subject)
          end.collect(&:id)

          # Don't need to confirm entries that were part of a commits kicked off by the staging record
          entries = affected_entries.reject {|entry| staging_record_start_operation_ids.include?(entry.commit_id) }

          # Don't need to confirm entries that were not part of a commit
          entries = entries.select(&:commit_id)

          entries = compact_entries(entries)
          entries = preload_records(entries)
          entries = filter_entries(entries)
          entries = group_entries(entries)
        end
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

      def preload_records(entries)
        entries.group_by(&:table_name).each do |table_name, group_entries|
          klass = CommitEntry.infer_class(table_name)
          records = klass.where(:id => group_entries.collect(&:record_id))
          records_by_id = records.collect {|r| [r.id, r] }.to_h
          group_entries.each do |entry|
            entry.record = records_by_id[entry.record_id]
          end
        end

        return entries
      end

      def cache(key, &block)
        if @cache.key?(key)
          @cache[key]
        else
          @cache[key] = block.call
        end
      end

      def clear_cache
        @cache.clear
      end
    end
  end
end
