module Stagehand
  module Staging
    class Checklist
      attr_reader :staging_record

      def initialize(staging_record, &confirmation_filter)
        @staging_record = staging_record
        @confirmation_filter = confirmation_filter
        @cache = {}
      end

      # Copies all the affected records from the staging database to the production database
      def synchronize
        entries = compact_entries(affected_entries)

        ActiveRecord::Base.transaction do
          entries.each do |entry|
            entry.delete_operation? ? Stagehand::Production.delete(entry) : Stagehand::Production.save(entry)
          end
          CommitEntry.where(:id => affected_entries.collect(&:id)).delete_all
        end

        return entries.count
      ensure
        clear_cache
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

      # Returns a list of records that exist in commits where the staging_record is not in the start operation
      def requires_confirmation
        cache(:requires_confirmation) { grouped_required_confirmation_entries.values.flatten.collect(&:record).compact }
      end

      def affected_records
        cache(:affected_records) { affected_entries.collect(&:record).uniq }
      end

      private

      def grouped_required_confirmation_entries
        cache(:grouped_required_confirmation_entries) do
          staging_record_start_operation_ids = affected_entries.select(&:start_operation?)
                                                               .select {|entry| entry.matches?(@staging_record) }
                                                               .collect(&:id)

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

      def affected_entries
        cache(:affected_entries) do
          entries = []
          entries += CommitEntry.uncontained.matching(@staging_record)
          if commit = first_commit_containing_record(@staging_record)
            entries += commit.content_entries
            entries += commit.related_entries
          end

          entries
        end
      end

      def first_commit_containing_record(staging_record)
        Commit.find(CommitEntry.contained.matching(staging_record).limit(1).pluck(:commit_id).first)
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
