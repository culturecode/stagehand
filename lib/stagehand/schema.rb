module Stagehand
  module Schema
    def self.add_stagehand!
      ActiveRecord::Schema.define do
        create_table :stagehand_commit_entries, :force => true do |t|
          t.integer :record_id
          t.string :table_name
          t.string :commit_identifier
          t.string :operation, :null => false
        end

        add_index :stagehand_commit_entries, :commit_identifier

        ActiveRecord::Base.connection.tables.each do |table_name|
          next if ['stagehand_commit_entries', 'schema_migrations'].include?(table_name)
          Stagehand::Schema.create_trigger(table_name, 'insert', 'NEW')
          Stagehand::Schema.create_trigger(table_name, 'update', 'NEW')
          Stagehand::Schema.create_trigger(table_name, 'delete', 'OLD')
        end
      end

      # Create trigger to initialize commit_identifier using a function
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS stagehand_commit_identifier_trigger;")
        ActiveRecord::Base.connection.execute("
        CREATE TRIGGER stagehand_commit_identifier_trigger BEFORE INSERT ON stagehand_commit_entries
        FOR EACH ROW SET NEW.commit_identifier = CONNECTION_ID();
      ")
    end

    private

    def self.create_trigger(table_name, trigger_action, record)
      trigger_name = "stagehand_commit_#{trigger_action}_trigger_#{table_name}"

      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS #{trigger_name};")
      ActiveRecord::Base.connection.execute("
        CREATE TRIGGER #{trigger_name} AFTER #{trigger_action.upcase} ON #{table_name}
        FOR EACH ROW
        BEGIN
          INSERT INTO stagehand_commit_entries (record_id, table_name, operation)
          VALUES (#{record}.id, '#{table_name}', '#{trigger_action}');
        END;
      ")
    end
  end
end
