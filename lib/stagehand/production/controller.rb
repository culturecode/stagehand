module Stagehand
  module Production
    module Controller
      extend ActiveSupport::Concern

      included do
        include Stagehand::ControllerExtensions

        skip_action_callback :use_staging_database
        around_action :use_production_database
      end
    end
  end
end
