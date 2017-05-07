require "stagehand/schema/statements"

module Stagehand
  module Schema
    extend self

    UNTRACKED_TABLES = ['schema_migrations', Stagehand::Staging::CommitEntry.table_name]

    def init_stagehand!(options = {})
      ActiveRecord::Schema.define do
        create_table :stagehand_commit_entries do |t|
          t.integer :record_id
          t.string :table_name
          t.string :operation, :null => false
          t.integer :commit_id
          t.string :session
          t.datetime :created_at
        end

        add_index :stagehand_commit_entries, :commit_id # Used for looking up all entries within a commit
        add_index :stagehand_commit_entries, [:record_id, :table_name] # Used for 'matching' scope
        add_index :stagehand_commit_entries, [:operation, :commit_id] # Used for looking up start entries, and 'not_in_progress' scope

        Stagehand::Schema.send :create_session_trigger
      end

      add_stagehand!(options)
    end

    def add_stagehand!(options = {})
      ActiveRecord::Schema.define do
        Stagehand::Schema.send :each_table, options do |table_name|
          Stagehand::Schema.send :create_operation_trigger, table_name, 'insert', 'NEW'
          Stagehand::Schema.send :create_operation_trigger, table_name, 'update', 'NEW'
          Stagehand::Schema.send :create_operation_trigger, table_name, 'delete', 'OLD'
        end
      end
    end

    def remove_stagehand!(options = {})
      ActiveRecord::Schema.define do
        Stagehand::Schema.send :each_table, options do |table_name|
          Stagehand::Schema.send :drop_trigger, table_name, 'insert'
          Stagehand::Schema.send :drop_trigger, table_name, 'update'
          Stagehand::Schema.send :drop_trigger, table_name, 'delete'
        end

        drop_table :stagehand_commit_entries unless options[:only].present?
      end
    end

    def has_stagehand?(table_name = nil)
      if UNTRACKED_TABLES.include?(table_name.to_s)
        return false
      elsif table_name
        trigger_exists?(table_name, 'insert')
      else
        ActiveRecord::Base.Connection.table_exists?(Stagehand::Staging::CommitEntry.table_name)
      end
    end

    private

    def each_table(options = {})
      table_names = ActiveRecord::Base.connection.tables
      table_names -= UNTRACKED_TABLES
      table_names -= Array(options[:except]).collect(&:to_s)
      table_names &= Array(options[:only]).collect(&:to_s) if options[:only].present?

      table_names.each do |table_name|
        yield table_name
      end
    end

    # Create trigger to initialize session using a function
    def create_session_trigger
      drop_trigger(:stagehand_commit_entries, :insert)
      create_trigger(:stagehand_commit_entries, :insert, :before, <<-SQL)
        SET NEW.session = CONNECTION_ID();
      SQL
    end

    def create_operation_trigger(table_name, trigger_event, record)
      return if trigger_exists?(table_name, trigger_event)

      create_trigger(table_name, trigger_event, :after, <<-SQL)
        BEGIN
          INSERT INTO stagehand_commit_entries (record_id, table_name, operation)
          VALUES (#{record}.id, '#{table_name}', '#{trigger_event}');
        END;
      SQL
    end

    def create_trigger(table_name, trigger_event, trigger_time, row_action)
      ActiveRecord::Base.connection.execute <<-SQL
        CREATE TRIGGER #{trigger_name(table_name, trigger_event)} #{trigger_time} #{trigger_event}
        ON #{table_name} FOR EACH ROW #{row_action}
      SQL
    end

    def drop_trigger(table_name, trigger_event)
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS #{trigger_name(table_name, trigger_event)};")
    end

    def trigger_exists?(table_name, trigger_event)
      ActiveRecord::Base.connection.select_one("SHOW TRIGGERS where `trigger` = '#{trigger_name(table_name, trigger_event)}'").present?
    end

    def trigger_name(table_name, trigger_event)
      "stagehand_#{trigger_event}_trigger_#{table_name}".downcase
    end
  end
end
