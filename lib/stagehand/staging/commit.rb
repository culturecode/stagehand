module Stagehand
  module Staging
    class Commit
      def self.all
        CommitEntry.start_operations.pluck(:id).collect {|id| find(id) }
      end

      def self.capture(subject_record = nil, &block)
        start_operation = start_commit(subject_record)
        block.call
        return end_commit(start_operation)
      rescue => e
        end_commit(start_operation)
        raise(e)
      end

      def self.containing(record)
        find(CommitEntry.contained.matching(record).pluck(:commit_id))
      end

      def self.find(start_ids)
        if start_ids.respond_to?(:each)
          start_ids.to_a.uniq.collect {|id| find(id) }.compact
        else
          new(start_ids)
        end
      rescue CommitNotFound
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
        @start_id, @end_id = CommitEntry.control_operations
          .where(:commit_id => start_id)
          .where('id >= ?', start_id).limit(2).pluck(:id)

        raise CommitNotFound unless @start_id && @end_id
      end

      def id
        @start_id
      end

      def include?(record)
        content_entries.where(:record_id => record.id, :table_name => record.class.table_name).exists?
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
        @related_commits ||= self.class.find(related_entries.collect(&:commit_id).uniq)
      end

      def related_entries
        return @related_entries if @related_entries
        @related_entries = []

        entries_to_spider = content_entries
        while entries_to_spider.present?
          matching_entries = CommitEntry.contained.matching(entries_to_spider)
          matching_commit_entries = CommitEntry.content_operations.where(:commit_id => matching_entries.collect(&:commit_id).uniq)
          entries_to_spider = matching_commit_entries - @related_entries
          @related_entries.concat(entries_to_spider)
        end

        @related_entries -= entries

        return @related_entries
      end

      def content_entries
        entries.content_operations
      end

      def entries
        CommitEntry.where(:id => @start_id..@end_id).where(:commit_id => id)
      end
    end
  end

  # EXCEPTIONS
  class CommitNotFound < StandardError; end
end
