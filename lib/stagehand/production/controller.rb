module Stagehand
  module Production
    module Controller
      extend ActiveSupport::Concern

      included do
        skip_action_callback :use_staging_database
        around_action :use_production_database
      end

      private

      def use_production_database(&block)
        Database.with_connection(Configuration.production_connection_name, &block)
      end
    end
  end
end
