module Stagehand
  module Staging
    class Commit
      attr_accessor :identifier

      def self.all
        CommitEntry.start_operations.pluck(:id).collect {|id| find(id) }
      end

      def self.capture(identifier = nil, &block)
        start_operation = CommitEntry.start_operations.create(:commit_identifier => identifier).reload
        identifier ||= "commit_#{start_operation.id}"
        block.call
      ensure
        CommitEntry.end_operations.create(:commit_identifier => identifier)
        commit = find(start_operation.id)
        commit.entries.update_all(:commit_identifier => identifier)
        commit.identifier = identifier

        return commit
      end

      def self.containing(record)
        with_identifier(CommitEntry.contained.matching(record).uniq.pluck(:commit_identifier))
      end

      def self.with_identifier(*identifiers)
        start_ids = CommitEntry.start_operations.where(:commit_identifier => identifiers.flatten.uniq).pluck(:id)
        start_ids.collect {|start_id| find(start_id) }
      end

      def self.find(start_id)
        new(start_id)
      rescue ActiveRecord::RecordNotFound
        raise Stagehand::CommitNotFound, "No commit with id #{start_id}"
      end

      def initialize(start_id)
        start_operation = CommitEntry.start_operations.find(start_id)
        @identifier = start_operation.commit_identifier
        @start_id = start_id
        @end_id = CommitEntry.end_operations.where(:commit_identifier => @identifier).where('id > ?', start_id).first!.id
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
        CommitEntry.where(:id => @start_id..@end_id).where(:commit_identifier => @identifier)
      end
    end
  end

  # EXCEPTIONS
  class CommitNotFound < StandardError; end
end
