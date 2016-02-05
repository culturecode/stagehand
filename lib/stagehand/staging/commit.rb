module Stagehand
  module Staging
    class Commit
      attr_reader :identifier

      def self.find(identifier)
        new(identifier)
      end

      def self.containing(record)
        commit_identifiers = CommitEntry.contained.matching(record).uniq.pluck(:commit_identifier)
        commit_identifiers.collect {|identifier| find(identifier) }
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
        entries.save_operations.pluck(:record_id, :table_name)
      end

      def destroyed
        entries.delete_operations.pluck(:record_id, :table_name)
      end

      def keys
        entries.pluck(:record_id, :table_name)
      end

      def entries
        range.content_operations.where(:commit_identifier => @identifier).uniq('record_id, table_name')
      end

      def ==(other)
        entries == other.entries
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

      private

      def commit(&block)
        enable_commit
        block.call
        disable_commit

        @identifier ||= "commit_#{@commit_start.id}"
        finalize_commit_entries
      end

      def recall
        @commit_start = CommitEntry.start_operations.where(:commit_identifier => @identifier).first!
        @commit_end = CommitEntry.end_operations.where(:commit_identifier => @identifier).first!

      rescue ActiveRecord::RecordNotFound
        raise Stagehand::CommitNotFound, "No commits matched the identifier: #{@identifier}"
      end

      def enable_commit
        @commit_start = CommitEntry.start_operations.create
      end

      def disable_commit
        @commit_end = CommitEntry.end_operations.create
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
