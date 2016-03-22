module Stagehand
  module Staging
    module Controller
      extend ActiveSupport::Concern

      included do
        skip_action_callback :use_production_database
        prepend_around_action :use_staging_database
      end

      # Creates a stagehand commit to log database changes associated with the given record
      def stage_changes(subject_record = nil, &block)
        Staging::Commit.capture(subject_record, &block)
      end

      # Syncs the given record and all affected records to the production database
      def sync_record(record)
        Stagehand::Staging::Synchronizer.sync_record(record)
      end

      private

      def use_staging_database(&block)
        Database.with_connection(Configuration.staging_connection_name, &block)
      end
    end
  end
end
