require 'stagehand/staging/commit'
require 'stagehand/staging/commit_entry'
require 'stagehand/staging/checklist'

module Stagehand
  module Staging
    mattr_writer :environment

    def self.environment
      @@environment || raise(StagingEnvironmentNotSet)
    end
  end

  # EXCEPTIONS
  class StagingEnvironmentNotSet < StandardError; end
end
