module Stagehand
  module Staging
    module Model
      extend ActiveSupport::Concern

      class_methods do
        def connection
          return super if Configuration.ghost_mode?

          if Stagehand::Database.connected_to_production?
            Stagehand::Database::StagingProbe.connection
          else
            ActiveRecord::Base.connection
          end
        end
      end
    end
  end
end
