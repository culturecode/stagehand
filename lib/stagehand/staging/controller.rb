module Stagehand
  module Staging
    module Controller
      extend ActiveSupport::Concern

      included do
        include InstanceMethods

        around_filter :perform_queries_on_staging
      end

      module InstanceMethods
        private

        # Causes queries to run on staging for the duration of the block
        # Does not affect models that have explicit establish_connection calls
        # Switches connection back to production after the block completes
        def perform_queries_on_staging
          ActiveRecord::Base.establish_connection(Stagehand::Staging.connection_name)
          yield
        ensure
          ActiveRecord::Base.establish_connection(Stagehand::Production.connection_name)
        end
      end
    end
  end
end
