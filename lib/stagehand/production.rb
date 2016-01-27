module Stagehand
  module Production
    mattr_accessor :environment

    class Record < ActiveRecord::Base; end

    def self.save(staging_record)
      prepare_to_modify(staging_record.class.table_name)

      production_record = Record.where(:id => staging_record.id).first_or_initialize
      production_record.update_attributes(staging_record.attributes)
      production_record
    end

    def self.destroy(staging_record, class_name = nil)
      case staging_record
      when ActiveRecord::Base
        prepare_to_modify(staging_record.class.table_name)
      else
        prepare_to_modify(class_name.constantize.table_name)
      end

      Record.where(:id => staging_record).delete_all
    end

    private

    def self.prepare_to_modify(table_name)
      connect_to_production_database
      Record.table_name = table_name
    end

    def self.connect_to_production_database
      Record.establish_connection(environment) unless @connection_established
      @connection_established = true
    end
  end
end
