module Stagehand
  module ControllerHelper

    # Creates a stagehand commit to log database changes associated with the given record
    def commit_staging_changes(subject_record = nil, &block)
      Staging::Commit.capture(subject_record, &block)
    end
  end
end
