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
          .update_all(:commit_id => start_operation.id)

        return new(start_operation.id)
      end

      public

      def initialize(start_id)
        @start_id, @end_id = CommitEntry.control_operations
          .limit(2)
          .where(:commit_id => start_id)
          .where('id >= ?', start_id)
          .reorder(:id => :asc)
          .pluck(:id)

        raise CommitNotFound unless @start_id && @end_id
      end

      def id
        @start_id
      end

      def include?(record)
        entries.where(:record_id => record.id, :table_name => record.class.table_name).exists?
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

      def entries
        CommitEntry.where(:id => @start_id..@end_id).where(:commit_id => id)
      end
    end
  end

  # EXCEPTIONS
  class CommitNotFound < StandardError; end
end
