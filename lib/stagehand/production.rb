module Stagehand
  module Production
    mattr_accessor :environment

    class Record < ActiveRecord::Base
      self.record_timestamps = false
    end

    def self.save(staging_record)
      production_record = lookup(staging_record).first_or_initialize
      production_record.update_attributes(staging_record.attributes)
      production_record
    end

    def self.destroy(staging_record, table_name = nil)
      lookup(staging_record, table_name).delete_all
    end

    def self.exists?(staging_record, table_name = nil)
      lookup(staging_record, table_name).exists?
    end

    # Returns true if the staging record's attributes are different from the production record's attributes
    # Returns true if the staging_record does not exist on production
    # Returns false if the staging record is identical to the production record
    def self.modified?(staging_record)
      production_attributes = Record.connection.select_one(lookup(staging_record))
      staging_attributes = staging_record.class.connection.select_one(staging_record.class.where(:id => staging_record.id))

      return production_attributes != staging_attributes
    end

    # Returns a scope that limits results any occurrences of the specified record.
    # Record can be specified by passing a staging record, or an id and table_name.
    def self.lookup(staging_record, table_name = nil)
      case staging_record
      when ActiveRecord::Base
        prepare_to_modify(staging_record.class.table_name)
      else
        prepare_to_modify(table_name)
      end

      return Record.where(:id => staging_record)
    end

    private

    def self.prepare_to_modify(table_name)
      raise "Can't prepare to modify production records without knowning the table_name" unless table_name.present?
      connect_to_production_database
      Record.table_name = table_name
    end

    def self.connect_to_production_database
      raise ProductionEnvironmentNotSet unless environment
      Record.establish_connection(environment) unless @connection_established
      @connection_established = true
    end
  end

  # EXCEPTIONS
  class ProductionEnvironmentNotSet < StandardError; end
end
