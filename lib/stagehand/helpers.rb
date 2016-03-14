module Stagehand
  module Key
    def self.generate(staging_record, table_name = nil)
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
  end

  module ControllerExtensions
    def use_staging_database(&block)
      Database.connect_to_database(Configuration.staging_connection_name, &block)
    end

    def use_production_database(&block)
      Database.connect_to_database(Configuration.production_connection_name, &block)
    end
  end

  module Database
    @@connection_name_stack = [Rails.env.to_sym]

    def self.connect_to_database(target_connection_name)
      changed = !(Configuration.ghost_mode || current_connection_name == target_connection_name.to_sym)

      @@connection_name_stack.push(target_connection_name.to_sym)
      Rails.logger.debug "Connecting to #{current_connection_name}"
      ActiveRecord::Base.establish_connection(current_connection_name) if changed

      yield
    ensure
      @@connection_name_stack.pop
      Rails.logger.debug "Restoring connection to #{current_connection_name}"
      ActiveRecord::Base.establish_connection(current_connection_name) if changed
    end

    private

    def self.current_connection_name
      @@connection_name_stack.last
    end
  end
end
