module Stagehand
  module Staging
    module Controller
      extend ActiveSupport::Concern
      include Stagehand::ControllerExtensions

      included do
        use_staging_database
      end

      # Creates a stagehand commit to log database changes associated with the given record
      def stage_changes(subject_record = nil, &block)
        Staging::Commit.capture(subject_record, &block)
      end

      # Syncs the given record and all affected records to the production database
      def sync_record(record)
        record.run_callbacks :sync do
          Stagehand::Staging::Synchronizer.sync_record(record)
        end
      end
    end
  end
end
