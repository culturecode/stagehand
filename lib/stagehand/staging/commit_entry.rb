module Stagehand
  module Staging
    class CommitEntry < ActiveRecord::Base
      attr_writer :record

      self.table_name = 'stagehand_commit_entries'

      START_OPERATION = 'commit_start'
      END_OPERATION = 'commit_end'
      INSERT_OPERATION = 'insert'
      UPDATE_OPERATION = 'update'
      DELETE_OPERATION = 'delete'

      CONTROL_OPERATIONS = [START_OPERATION, END_OPERATION]
      CONTENT_OPERATIONS = [INSERT_OPERATION, UPDATE_OPERATION, DELETE_OPERATION]
      SAVE_OPERATIONS = [INSERT_OPERATION, UPDATE_OPERATION]

      scope :start_operations,      lambda { where(:operation => START_OPERATION) }
      scope :end_operations,        lambda { where(:operation => END_OPERATION) }
      scope :control_operations,    lambda { where(:operation => CONTROL_OPERATIONS) }
      scope :content_operations,    lambda { where(:operation => CONTENT_OPERATIONS) }
      scope :save_operations,       lambda { where(:operation => SAVE_OPERATIONS) }
      scope :delete_operations,     lambda { where(:operation => DELETE_OPERATION) }
      scope :with_record,           lambda { where.not(:record_id => nil) }
      scope :uncontained,           lambda { where(:commit_id => nil) }
      scope :contained,             lambda { where.not(:commit_id => nil) }
      scope :no_newer_than,         lambda {|entry| where("id <= ?", entry) }
      scope :in_progress,           lambda { joins_active_commits }
      scope :not_in_progress,       lambda { joins_active_commits("LEFT OUTER").where("active_commits.commit_id IS NULL") }
      scope :with_uncontained_keys, lambda { uncontained.joins_contained("LEFT OUTER").where("contained.record_id IS NULL") }

      def self.joins_active_commits(type = "INNER")
        joins("#{type} JOIN (#{ unscoped.select('session, MAX(id) AS commit_id').uncontained.start_operations.group('session').to_sql }) AS active_commits
               ON active_commits.session = #{table_name}.session AND active_commits.commit_id <= #{table_name}.id")
      end

      def self.joins_contained(type = "INNER")
        joins("#{type} JOIN (#{ unscoped.contained.select('record_id, table_name').distinct.to_sql}) AS contained
               ON contained.record_id = #{table_name}.record_id AND contained.table_name = #{table_name}.table_name")
      end

      def self.matching(object)
        keys = Array.wrap(object).collect {|entry| Stagehand::Key.generate(entry) }.compact
        sql = []
        interpolates = []
        groups = keys.group_by(&:first)

        # If passed control operation commit entries, ensure they are returned since their keys match the CommitEntry's primary key
        if commit_entry_group = groups.delete(CommitEntry.table_name)
          sql << 'id IN (?)'
          interpolates << commit_entry_group.collect(&:last)
        end

        groups.each do |table_name, keys|
          sql << "(table_name = ? AND record_id IN (?))"
          interpolates << table_name
          interpolates << keys.collect(&:last)
        end

        return keys.present? ? where(sql.join(' OR '), *interpolates) : none
      end

      def self.infer_class(table_name, record_id = nil)
        classes = ActiveRecord::Base.descendants.select {|klass| klass.table_name == table_name }
        classes.delete(Stagehand::Production::Record)
        root_class = classes.first || table_name.classify.constantize # Try loading the class if it isn't loaded yet

        if record_id && record = root_class.find_by_id(record_id)
          klass = record.class
        end

        return klass || root_class
      rescue NameError
        raise(IndeterminateRecordClass, "Can't determine class from table name: #{table_name}")
      end

      validates_presence_of :record_id, :if => :table_name
      validates_presence_of :table_name, :if => :record_id

      def record
        @record ||= delete_operation? ? build_deleted_record : record_class.find_by_id(record_id) if record_id?
      end

      def control_operation?
        operation.in?(CONTROL_OPERATIONS)
      end

      def content_operation?
        operation.in?(CONTENT_OPERATIONS)
      end

      def save_operation?
        operation.in?(SAVE_OPERATIONS)
      end

      def insert_operation?
        operation == INSERT_OPERATION
      end

      def update_operation?
        operation == UPDATE_OPERATION
      end

      def delete_operation?
        operation == DELETE_OPERATION
      end

      def start_operation?
        operation == START_OPERATION
      end

      def end_operation?
        operation == END_OPERATION
      end

      def matches?(others)
        Array.wrap(others).any? {|other| key == Stagehand::Key.generate(other) }
      end

      def key
        @key ||= Stagehand::Key.generate(self)
      end

      def record_class
        @record_class ||= infer_class
      rescue IndeterminateRecordClass
        @record_class ||= self.class.build_missing_model(table_name)
      end

      def production_record
        @production_record ||= Stagehand::Production.find(record_id, table_name)
      end

      private

      def infer_class
        inferred_class = self.class.infer_class(table_name, record_id)
        sti_inferred_class = production_record.read_attribute(inferred_class.inheritance_column) if delete_operation?
        sti_inferred_class ? sti_inferred_class.constantize : inferred_class
      end

      def build_deleted_record
        return unless production_record
        deleted_record = production_record.becomes(record_class)
        deleted_record.readonly!
        deleted_record.singleton_class.include(DeletedRecord)
        return deleted_record
      end

      def self.build_missing_model(table_name)
        raise MissingTable, "Can't find table specified in entry: #{table_name}" unless Database.staging_connection.tables.include?(table_name)
        klass = Class.new(ActiveRecord::Base) { self.table_name = table_name }
        DummyClass.const_set(table_name.classify, klass)
      end
    end
  end

  # UTILITY MODULES

  module DummyClass; end # A namespace for dummy classes of records with an IndeterminateRecordClass
  module DeletedRecord; end # Serves as a way of tagging an instance to see if it is_a?(Stagehand::DeletedRecord)

  # EXCEPTIONS

  class IndeterminateRecordClass < StandardError; end
  class MissingTable < StandardError; end
end
