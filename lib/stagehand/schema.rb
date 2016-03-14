module Stagehand
  module Schema
    def self.add_stagehand!(options = {})
      ActiveRecord::Schema.define do
        unless Stagehand::Staging::CommitEntry.table_exists?
          create_table :stagehand_commit_entries do |t|
            t.integer :record_id
            t.string :table_name
            t.string :operation, :null => false
            t.integer :commit_id
            t.string :session
          end

          add_index :stagehand_commit_entries, :commit_id
          add_index :stagehand_commit_entries, :operation

          # Create trigger to initialize session using a function
          ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS stagehand_session_trigger;")
          ActiveRecord::Base.connection.execute("
          CREATE TRIGGER stagehand_session_trigger BEFORE INSERT ON stagehand_commit_entries
          FOR EACH ROW SET NEW.session = CONNECTION_ID();")
        end

        table_names = ActiveRecord::Base.connection.tables
        table_names -= [Stagehand::Staging::CommitEntry.table_name, 'schema_migrations']
        table_names -= Array(options[:except]).collect(&:to_s)
        table_names &= Array(options[:only]).collect(&:to_s) if options[:only].present?

        table_names.each do |table_name|
          Stagehand::Schema.drop_trigger(table_name, 'insert')
          Stagehand::Schema.drop_trigger(table_name, 'update')
          Stagehand::Schema.drop_trigger(table_name, 'delete')

          Stagehand::Schema.create_trigger(table_name, 'insert', 'NEW')
          Stagehand::Schema.create_trigger(table_name, 'update', 'NEW')
          Stagehand::Schema.create_trigger(table_name, 'delete', 'OLD')
        end
      end
    end

    def self.remove_stagehand!(options = {})
      ActiveRecord::Schema.define do
        table_names = ActiveRecord::Base.connection.tables
        table_names &= Array(options[:only]).collect(&:to_s) if options[:only].present?

        table_names.each do |table_name|
          Stagehand::Schema.drop_trigger(table_name, 'insert')
          Stagehand::Schema.drop_trigger(table_name, 'update')
          Stagehand::Schema.drop_trigger(table_name, 'delete')
        end

        drop_table :stagehand_commit_entries unless options[:only].present?
      end
    end

    private

    def self.create_trigger(table_name, trigger_action, record)
      ActiveRecord::Base.connection.execute("
        CREATE TRIGGER #{trigger_name(table_name, trigger_action)} AFTER #{trigger_action.upcase} ON #{table_name}
        FOR EACH ROW
        BEGIN
          INSERT INTO stagehand_commit_entries (record_id, table_name, operation)
          VALUES (#{record}.id, '#{table_name}', '#{trigger_action}');
        END;
      ")
    end

    def self.drop_trigger(table_name, trigger_action)
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS #{trigger_name(table_name, trigger_action)};")
    end

    def self.trigger_name(table_name, trigger_action)
      "stagehand_#{trigger_action}_trigger_#{table_name}"
    end
  end
end
