module Stagehand
  module Staging
    class Commit
      def self.all
        CommitEntry.end_operations.pluck(:commit_id).collect {|id| find(id) }.compact
      end

      def self.empty
        all.select(&:empty?)
      end

      def self.capturing?
        !!@capturing
      end

      def self.capture(subject_record = nil, except: [], &block)
        @capturing = true
        start_operation = start_commit(subject_record)
        init_session!(start_operation)

        begin
          block.call(start_operation)
        rescue => e
          end_commit(start_operation, except) unless e.is_a?(CommitError)
          raise(e)
        else
          return end_commit(start_operation, except)
        end
      ensure
        @capturing = false
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

        # Make it easy to set the subject for the duration of the commit block
        def start_operation.subject=(record)
          if record&.id
            raise NonStagehandSubject unless record.has_stagehand?
            self.assign_attributes :record_id => record.id, :table_name => record.class.table_name
          end
          save!
        end

        start_operation.subject = subject_record

        return start_operation
      end

      # Sets the commit_id on all the entries between the start and end op.
      # Returns the commit object for those entries
      def self.end_commit(start_operation, except)
        end_operation = CommitEntry.end_operations.create(:session => start_operation.session)

        scope = CommitEntry.where(:id => start_operation.id..end_operation.id, :session => start_operation.session)
        if except.present? && Array(except).collect(&:to_s).exclude?(start_operation.table_name)
          scope = scope.where('table_name NOT IN (?) OR table_name IS NULL', except)
        end
        scope.update_all(:commit_id => start_operation.id)

        return new(start_operation.id)
      end

      # Reload to ensure session set by the database is read by ActiveRecord
      def self.init_session!(entry)
        entry.reload
        raise BlankCommitEntrySession unless entry.session.present?
      end

      public

      def initialize(start_id)
        @start_id, @end_id = CommitEntry.control_operations
          .limit(2)
          .where(:commit_id => start_id)
          .where('id >= ?', start_id)
          .reorder(:id => :asc)
          .pluck(:id)

        return if @start_id && @end_id

        missing = []
        missing << CommitEntry::START_OPERATION unless @start_id
        missing << CommitEntry::END_OPERATION unless @end_id

        raise CommitNotFound, "Couldn't find #{missing.join(', ')} entry for Commit #{start_id}"
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

      def subject
        entries.sort_by(&:id).first.record
      end

      def empty?
        entries.content_operations.empty?
      end

      def destroy
        entries.delete_all
      end
    end
  end

  # EXCEPTIONS
  class CommitError < StandardError; end
  class CommitNotFound < CommitError; end
  class BlankCommitEntrySession < CommitError; end
  class NonStagehandSubject < CommitError; end
end
