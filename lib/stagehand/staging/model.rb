module Stagehand
  module Staging
    module Model
      extend ActiveSupport::Concern

      included do
        Stagehand::Database.set_connection_for_model(self, Configuration.staging_connection_name)
      end
    end
  end
end
