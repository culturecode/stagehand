module Stagehand
  module ControllerHelper

    def commit_entry_subtree(commit)
      commits = [commit]
      index = 0

      while index < commits.length
        commits.concat subcommits_of(commits[index])
        commits.uniq!(&:identifier)
      end

      commits.flat_map(&:entries)
    end

    # Returns commits for records that were part of the given commit
    def subcommits_of(commit)
      subcommits = commit.entries.collect {|entry| staging_changes_for(entry) }
      subcommits.select {|subcommit| subcommit && subcommit.identifier != commit.identifier }
    end

    # Creates a stagehand commit to log database changes associated with the given record
    def commit_staging_changes_for(record, &block)
      Staging::Commit.new(commit_identifier_for(record), &block)
    end

    # Loads a stagehand commit with log entries from all the given record's commits
    def staging_changes_for(record)
      Staging::Commit.find(commit_identifier_for(record))
    rescue Stagehand::CommitNotFound
    end

    private

    def commit_identifier_for(record)
      case record
      when CommitEntry
        "#{record.record_id}/#{record.table_name}"
      else
        "#{record.id}/#{record.class.table_name}"
      end
    end
  end
end
