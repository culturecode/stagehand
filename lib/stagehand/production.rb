require 'stagehand/production/controller'

module Stagehand
  module Production
    extend self

    # Outputs a symbol representing the status of the staging record as it exists in the production database
    def status(staging_record)
      if !exists?(staging_record)
        :new
      elsif modified?(staging_record)
        :modified
      else
        :not_modified
      end
    end

    def save(staging_record)
      attributes = staging_record_attributes(staging_record)

      return unless attributes.present?

      is_new = lookup(staging_record).update_all(attributes).zero?

      # Ensure we always return a record, even when updating instead of creating
      Record.new.tap do |record|
        record.assign_attributes(attributes)
        record.save if is_new
      end
    end

    def delete(staging_record, table_name = nil)
      lookup(staging_record, table_name).delete_all
    end

    def exists?(staging_record, table_name = nil)
      lookup(staging_record, table_name).exists?
    end

    # Returns true if the staging record's attributes are different from the production record's attributes
    # Returns true if the staging_record does not exist on production
    # Returns false if the staging record is identical to the production record
    def modified?(staging_record)
      production_record_attributes(staging_record) != staging_record_attributes(staging_record)
    end

    # Returns a scope that limits results any occurrences of the specified record.
    # Record can be specified by passing a staging record, or an id and table_name.
    def lookup(staging_record, table_name = nil)
      table_name, id = Stagehand::Key.generate(staging_record, table_name)
      prepare_to_modify(table_name)
      return Record.where(:id => id)
    end

    private

    def prepare_to_modify(table_name)
      raise "Can't prepare to modify production records without knowning the table_name" unless table_name.present?
      Record.establish_connection(Configuration.production_connection_name) and @connection_established = true unless @connection_established
      Record.table_name = table_name
    end

    def production_record_attributes(staging_record)
      Record.connection.select_one(lookup(staging_record))
    end

    def staging_record_attributes(staging_record, table_name = nil)
      table_name, id = Stagehand::Key.generate(staging_record, table_name)
      Stagehand::Staging::CommitEntry.connection.select_one("SELECT * FROM #{table_name} WHERE id = #{id}")
    end

    # CLASSES

    class Record < ActiveRecord::Base
      self.record_timestamps = false
    end
  end
end
