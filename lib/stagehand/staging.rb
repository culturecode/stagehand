require 'stagehand/staging/commit'
require 'stagehand/staging/commit_entry'
require 'stagehand/staging/checklist'
require 'stagehand/staging/controller'

module Stagehand
  module Staging
    mattr_writer :connection_name

    def self.connection_name
      @@connection_name || raise(StagingConnectionNameNotSet)
    end
  end

  # EXCEPTIONS
  class StagingConnectionNameNotSet < StandardError; end
end
