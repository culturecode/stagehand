require 'stagehand/production/controller'

module Stagehand
  module Production
    extend self

    # Outputs a symbol representing the status of the staging record as it exists in the production database
    def status(staging_record, table_name = nil)
      if !exists?(staging_record, table_name)
        :new
      elsif modified?(staging_record, table_name)
        :modified
      else
        :not_modified
      end
    end

    def save(staging_record, table_name = nil)
      attributes = staging_record_attributes(staging_record, table_name)

      return unless attributes.present?

      write(staging_record, attributes, table_name)
    end

    def write(staging_record, attributes, table_name = nil)
      Connection.with_production_writes do
        is_new = matching(staging_record, table_name).update_all(attributes).zero?

        # Ensure we always return a record, even when updating instead of creating
        Record.new.tap do |record|
          record.assign_attributes(attributes)
          record.id = Stagehand::Key.generate(staging_record, :table_name => table_name).last unless record.id
          record.save if is_new
        end
      end
    end

    def delete(staging_record, table_name = nil)
      Connection.with_production_writes do
        matching(staging_record, table_name).delete_all
      end
    end

    def exists?(staging_record, table_name = nil)
      matching(staging_record, table_name).exists?
    end

    # Returns true if the staging record's attributes are different from the production record's attributes
    # Returns true if the staging_record does not exist on production
    # Returns false if the staging record is identical to the production record
    def modified?(staging_record, table_name = nil)
      production_record_attributes(staging_record, table_name) != staging_record_attributes(staging_record, table_name)
    end

    def find(*args)
      matching(*args).first
    end

    # Returns a scope that limits results any occurrences of the specified record.
    # Record can be specified by passing a staging record, or an id and table_name.
    def matching(staging_record, table_name = nil)
      table_name, id = Stagehand::Key.generate(staging_record, :table_name => table_name)
      prepare_to_modify(table_name)
      return Record.where(:id => id)
    end

    private

    def production_record_attributes(staging_record, table_name = nil)
      Record.connection.select_one(matching(staging_record, table_name))
    end

    def staging_record_attributes(staging_record, table_name = nil)
      table_name, id = Stagehand::Key.generate(staging_record, :table_name => table_name)
      prepare_to_read(table_name)
      staging_record = StagingRecordReader.find_by_id(id)
      return if staging_record.blank?
      staging_record.attributes.except(*ignored_columns(table_name))
    end

    def ignored_columns(table_name)
      Array.wrap(Configuration.ignored_columns[table_name]).map(&:to_s)
    end

    def prepare_to_read(table_name)
      raise "Can't prepare to read staging records without knowning the table_name" unless table_name.present?
      StagingRecordReader.table_name = table_name
    end

    def prepare_to_modify(table_name)
      raise "Can't prepare to modify production records without knowning the table_name" unless table_name.present?
      Record.table_name = table_name
    end

    # CLASSES

    class Record < Stagehand::Database::ProductionProbe
      self.record_timestamps = false
      self.inheritance_column = nil
    end

    class StagingRecordReader < Stagehand::Database::StagingProbe
      self.inheritance_column = nil
    end
  end
end
