module Stagehand
  module Staging
    class Commit
      def self.all
        CommitEntry.start_operations.pluck(:id).collect {|id| find(id) }
      end

      def self.capture(subject_record = nil, &block)
        start_operation = start_commit(subject_record)
        block.call
      ensure
        return end_commit(start_operation)
      end

      def self.containing(record)
        find(CommitEntry.contained.matching(record).pluck(:commit_id))
      end

      def self.find(start_ids)
        if start_ids.respond_to?(:to_a)
          start_ids.uniq.collect {|id| find(id) }.compact
        else
          new(start_ids)
        end
      rescue ActiveRecord::RecordNotFound
      end

      private

      def self.start_commit(subject_record)
        start_operation = CommitEntry.start_operations.new

        if subject_record
          start_operation.record_id = subject_record.id
          start_operation.table_name = subject_record.class.table_name
        end

        start_operation.save

        return start_operation.reload # Reload to ensure session is set
      end

      # Sets the commit_id on all the entries between the start and end op.
      # Returns the commit object for those entries
      def self.end_commit(start_operation)
        end_operation = CommitEntry.end_operations.create(:session => start_operation.session)

        CommitEntry
          .where(:id => start_operation.id..end_operation.id)
          .where(:session => start_operation.session)
          .update_all(:commit_id => start_operation.id, :session => nil)

        return new(start_operation.id)
      end

      public

      def initialize(start_id)
        start_operation = CommitEntry.start_operations.find(start_id)
        @start_id = start_id
        @end_id = CommitEntry.end_operations.where(:commit_id => start_id).where('id > ?', start_id).first!.id
      end

      def id
        @start_id
      end

      def include?(record)
        content_entries.where(:record_id => record.id, :table_name => record.class.table_name).exists?
      end

      def keys
        content_entries.pluck(:record_id, :table_name).uniq
      end

      def hash
        id
      end

      def eql?(other)
        self == other
      end

      def ==(other)
        id == other.id
      end

      def related_commits
        related_keys # ensure we've processed the related keys first
        @related_commits
      end

      def related_keys
        return @related_keys if @related_keys
        @related_commits = []
        @related_keys = []
        entries_to_spider = keys

        while entries_to_spider.present?
          current_entry = entries_to_spider.shift
          next if @related_keys.include?(current_entry)

          @related_keys << current_entry
          @related_commits.concat self.class.containing(current_entry)
          entries_to_spider.concat self.class.containing(current_entry).flat_map(&:keys)
          entries_to_spider.uniq!
        end

        @related_commits.uniq!

        return @related_keys
      end

      def content_entries
        entries.content_operations
      end

      def entries
        CommitEntry.where(:id => @start_id..@end_id).where(:commit_id => @start_id)
      end
    end
  end

  # EXCEPTIONS
  class CommitNotFound < StandardError; end
end
