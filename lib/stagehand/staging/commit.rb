module Stagehand
  module Staging
    class Commit
      attr_reader :identifier

      def self.find(identifier)
        new(identifier)
      end

      def initialize(identifier = nil, &block)
        @identifier = identifier

        if block_given?
          commit(&block)
        else
          recall
        end
      end

      def include?(record)
        entries.where(:record_id => record.id, :table_name => record.class.table_name).exists?
      end

      def saved
        entries.where(:operation => ['insert', 'update']).pluck(:record_id, :table_name)
      end

      def destroyed
        entries.where(:operation => 'delete').pluck(:record_id, :table_name)
      end

      def entries
        range.where(:operation => ['insert', 'update', 'delete'], :commit_identifier => @identifier).uniq('record_id, table_name')
      end

      def ==(other)
        entries == other.entries
      end

      private

      def commit(&block)
        enable_commit
        block.call
        disable_commit

        @identifier ||= "commit_#{@commit_start.id}"
        finalize_commit_entries
      end

      def recall
        @commit_start = CommitEntry.where(:commit_identifier => @identifier, :operation => :commit_start).first!
        @commit_end = CommitEntry.where(:commit_identifier => @identifier, :operation => :commit_end).first!

      rescue ActiveRecord::RecordNotFound
        raise Stagehand::CommitNotFound, "No commits matched the identifier: #{@identifier}"
      end

      def enable_commit
        @commit_start = CommitEntry.create(:operation => :commit_start)
      end

      def disable_commit
        @commit_end = CommitEntry.create(:operation => :commit_end)
      end

      def finalize_commit_entries
        unfinalized_entries.update_all(:commit_identifier => @identifier)
      end

      def unfinalized_entries
        range.where(:commit_identifier => @commit_start.commit_identifier)
      end

      def range
        CommitEntry.where(:id => @commit_start.id..@commit_end.id)
      end
    end
  end

  # EXCEPTIONS
  class CommitNotFound < StandardError; end
end
