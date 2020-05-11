module Stagehand
  module Staging
    module Model
      extend ActiveSupport::Concern

      included do
        Stagehand::Configuration.staging_model_tables << table_name
      end

      class_methods do
        def connection
          if Configuration.ghost_mode?
            super
          elsif Stagehand::Database.connected_to_staging?
            ActiveRecord::Base.connection
          else
            Stagehand::Database::StagingProbe.connection
          end
        end
      end
    end
  end
end
