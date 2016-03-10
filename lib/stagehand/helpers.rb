module Stagehand
  def self.extract_key(staging_record, table_name = nil)
    case staging_record
    when Staging::CommitEntry
      id = staging_record.record_id
      table_name = staging_record.table_name
    when ActiveRecord::Base
      id = staging_record.id
      table_name = staging_record.class.table_name
    else
      id = staging_record
      end

      raise 'Invalid input' unless table_name && id

      return [table_name, id]
    end

  module ControllerExtensions
    def use_staging_database(&block)
      connect_to_database(Stagehand::Staging.connection_name, Stagehand::Production.connection_name, &block)
    end

    def use_production_database(&block)
      connect_to_database(Stagehand::Production.connection_name, Stagehand::Staging.connection_name, &block)
    end

    private

    def connect_to_database(target_connection_name, original_connection_name)
      ActiveRecord::Base.establish_connection(target_connection_name)
      yield
    ensure
      ActiveRecord::Base.establish_connection(original_connection_name)
    end
  end
end
