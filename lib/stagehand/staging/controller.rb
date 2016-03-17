module Stagehand
  module Staging
    module Controller
      extend ActiveSupport::Concern

      included do
        skip_action_callback :use_production_database
        prepend_around_action :use_staging_database
      end

      private

      def use_staging_database(&block)
        Database.with_connection(Configuration.staging_connection_name, &block)
      end
    end
  end
end
