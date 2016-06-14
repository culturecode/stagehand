module Stagehand
  module ControllerExtensions
    extend ActiveSupport::Concern

    class_methods do
      def use_staging_database(options = {})
        skip_action_callback :use_production_database, options
        prepend_around_action :use_staging_database, options
      end

      def use_production_database(options = {})
        skip_action_callback :use_staging_database, options
        prepend_around_action :use_production_database, options
      end
    end

    private

    def use_staging_database(&block)
      use_database(Configuration.staging_connection_name, &block)
    end

    def use_production_database(&block)
      use_database(Configuration.production_connection_name, &block)
    end

    def use_database(connection_name, &block)
      if Configuration.ghost_mode?
        block.call
      else
        Database.with_connection(connection_name, &block)
      end
    end
  end
end
