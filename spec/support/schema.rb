RSpec.configure do |config|
  config.before(:suite) do
    # Drop all tables
    table_names = ActiveRecord::Base.connection.tables
    table_names -= ['schema_migrations']
    ActiveRecord::Schema.define do
      table_names.each {|table_name| drop_table(table_name) }
    end

    # Create tables in the test and production database so we test copying from one to the other
    [Stagehand.configuration.staging_connection_name, Stagehand.configuration.production_connection_name].each do |connection_name|
      ActiveRecord::Base.establish_connection connection_name

      ActiveRecord::Schema.define do
        create_table :source_records, :force => true, :stagehand => true do |t|
          t.string :name
          t.string :type
          t.timestamps :null => true
        end
      end
    end

    ActiveRecord::Base.establish_connection(Stagehand.configuration.staging_connection_name)

    # Create the model
    class SourceRecord < ActiveRecord::Base; end
    class STISourceRecord < SourceRecord; end

    # Add stagehand
    Stagehand::Schema.add_stagehand!

    ActiveRecord::Base.establish_connection(:test)
  end
end
