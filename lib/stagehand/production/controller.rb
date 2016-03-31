module Stagehand
  module Production
    module Controller
      extend ActiveSupport::Concern
      include Stagehand::ControllerExtensions

      included do
        use_production_database
      end
    end
  end
end
