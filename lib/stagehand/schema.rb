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
        table_names = ActiveRecord::Base.connection.tables
        table_names -= UNTRACKED_TABLES
        table_names -= Array(options[:except]).collect(&:to_s)
        table_names &= Array(options[:only]).collect(&:to_s) if options[:only].present?

        table_names.each do |table_name|
          Stagehand::Schema.send :create_operation_trigger, table_name, 'insert', 'NEW'
          Stagehand::Schema.send :create_operation_trigger, table_name, 'update', 'NEW'
          Stagehand::Schema.send :create_operation_trigger, table_name, 'delete', 'OLD'
        end
      end
    end

    def remove_stagehand!(options = {})
      ActiveRecord::Schema.define do
        table_names = ActiveRecord::Base.connection.tables
        table_names &= Array(options[:only]).collect(&:to_s) if options[:only].present?

        table_names.each do |table_name|
          Stagehand::Schema.send :drop_trigger, table_name, 'insert'
          Stagehand::Schema.send :drop_trigger, table_name, 'update'
          Stagehand::Schema.send :drop_trigger, table_name, 'delete'
        end

        drop_table :stagehand_commit_entries unless options[:only].present?
      end
    end

    def has_stagehand?(table_name = nil)
      if table_name
        trigger_exists?(table_name, 'insert')
      else
        ActiveRecord::Base.Connection.table_exists?(Stagehand::Staging::CommitEntry.table_name)
      end
    end

    private

    # Create trigger to initialize session using a function
    def create_session_trigger
      drop_trigger(:stagehand_commit_entries, :session)
      create_trigger(:stagehand_commit_entries, :session) do
        <<-SQL
          BEFORE INSERT ON stagehand_commit_entries FOR EACH ROW SET NEW.session = CONNECTION_ID();
        SQL
      end
    end

    def create_operation_trigger(table_name, trigger_action, record)
      return if trigger_exists?(table_name, trigger_action)

      create_trigger(table_name, trigger_action) do
        <<-SQL
          AFTER #{trigger_action.upcase} ON #{table_name}
          FOR EACH ROW
          BEGIN
            INSERT INTO stagehand_commit_entries (record_id, table_name, operation)
            VALUES (#{record}.id, '#{table_name}', '#{trigger_action}');
          END;
        SQL
      end
    end

    def create_trigger(table_name, trigger_action, &block)
      ActiveRecord::Base.connection.execute("CREATE TRIGGER #{trigger_name(table_name, trigger_action)} #{block.call}")
    end

    def drop_trigger(table_name, trigger_action)
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS #{trigger_name(table_name, trigger_action)};")
    end

    def trigger_exists?(table_name, trigger_action)
      ActiveRecord::Base.connection.select_one("SHOW TRIGGERS where `trigger` = '#{trigger_name(table_name, trigger_action)}'").present?
    end

    def trigger_name(table_name, trigger_action)
      "stagehand_#{trigger_action}_trigger_#{table_name}".downcase
    end
  end
end
