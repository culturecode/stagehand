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

        begin
          block.call(start_operation)
        rescue Interrupt => e # Prevent Ctrl + c in the console from causing the session commit id to be set for subsequent uncontained commit entries
          set_session_commit_id(nil) # Stop recording entries to this commit
          raise(e)
        rescue => e
          end_commit(start_operation, except) unless e.is_a?(CommitError) || e.is_a?(ActiveRecord::Rollback)
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
        set_session_commit_id(start_operation.commit_id)

        return start_operation
      end

      # Sets the commit_id on all the entries between the start and end op.
      # Returns the commit object for those entries
      def self.end_commit(start_operation, except)
        scope = CommitEntry.where(:commit_id => start_operation.id)

        # Remove any commit entries that are supposed to be excluded from the commit
        if except.present? && Array(except).collect(&:to_s).exclude?(start_operation.table_name)
          scope.content_operations.where(:table_name => except).update_all(:commit_id => nil)
        end

        end_operation = scope.end_operations.create
        set_session_commit_id(nil) # Stop recording entries to this commit

        if scope.control_operations.count < 2 # Unless we found at least 2 entries (start and end), abort the commit
          CommitEntry.logger.warn "Commit entries not found for Commit #{start_operation.id}. Was the Commit rolled back in a transaction?"
          end_operation.delete
          return
        end

        return new(start_operation.id)
      end

      # Ensure all entries created on this connection from now on match the given commit_id
      def self.set_session_commit_id(commit_id)
        CommitEntry.connection.execute <<~SQL
          SET @stagehand_commit_id = #{commit_id || 'NULL'};
        SQL
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
        missing << CommitEntry::START_OPERATION unless @start_id == start_id
        missing << CommitEntry::END_OPERATION if @start_id == start_id

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
  class NonStagehandSubject < CommitError; end
end
