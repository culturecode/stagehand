module Stagehand
  module ControllerHelper

    # Creates a stagehand commit to log database changes associated with the given record
    def commit_staging_changes_for(record, &block)
      Staging::Commit.capture(commit_identifier_for(record), &block)
    end

    private

    def commit_identifier_for(record)
      case record
      when Stagehand::Staging::CommitEntry
        "#{record.record_id}/#{record.table_name}"
      else
        "#{record.id}/#{record.class.table_name}"
      end
    end
  end
end
