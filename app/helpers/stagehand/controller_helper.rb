module Stagehand
  module ControllerHelper

    # Creates a stagehand commit to log database changes associated with the given record
    def commit_staging_changes(&block)
      Staging::Commit.capture(&block)
    end
  end
end
