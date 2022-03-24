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
        rescue Exception => e # Rescue Exception because we don't want to swallow them by returning from the ensure block
          raise(e)
        ensure
          commit = end_commit(start_operation, except) unless e.is_a?(CommitError) || e.is_a?(ActiveRecord::Rollback)

          return commit unless e
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

        # We perform a read to determine the ids that are meant to be part of our Commit in order to avoid acquiring
        # write locks on commit entries between the start and end entry that don't belong to our session. Otherwise, we
        # risk a deadlock if another process manipulates entries between our start and end while we have a range lock.
        entries = CommitEntry.where(id: scope.pluck(:id))

        updated_count = entries.update_all(:commit_id => start_operation.id)
        if updated_count < 2 # Unless we found at least 2 entries (start and end), abort the commit
          CommitEntry.logger.warn "Commit entries not found for Commit #{start_operation.id}. Was the Commit rolled back in a transaction?"
          end_operation.delete
          return nil
        elsif updated_count == 2 # Destroy empty commit
          entries.delete_all
          return nil
        else
          return new(start_operation.id)
        end
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

      def subject
        start_entry.record
      end

      def start_entry
        CommitEntry.find(@start_id)
      end

      def end_entry
        entries.end_operations.first
      end

      def empty?
        entries.content_operations.empty?
      end

      def destroy
        entries.delete_all
      end

      def entries
        CommitEntry.where(:id => @start_id..@end_id).where(:commit_id => id)
      end
    end
  end

  # EXCEPTIONS
  class CommitError < StandardError; end
  class CommitNotFound < CommitError; end
  class BlankCommitEntrySession < CommitError; end
  class NonStagehandSubject < CommitError; end
end
