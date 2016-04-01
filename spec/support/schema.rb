RSpec.configure do |config|
  config.before(:suite) do

    # Create tables in the test and production database so we test copying from one to the other
    [Stagehand.configuration.staging_connection_name, Stagehand.configuration.production_connection_name].each do |connection_name|

      Stagehand::Database.with_connection(connection_name) do

        ActiveRecord::Schema.define do
          ActiveRecord::Base.connection.tables.each {|table_name| drop_table(table_name) }

          create_table :schema_migrations, :id => false do |t|
            t.string :version
          end

          create_table :source_records, :force => true do |t|
            t.string :name
            t.string :type
            t.timestamps :null => true
          end
        end
      end

    end

    ActiveRecord::Base.establish_connection(Stagehand.configuration.staging_connection_name)

    # Add stagehand to the staging database
    Stagehand::Schema.init_stagehand!

    # Create the model
    class SourceRecord < ActiveRecord::Base; end
    class STISourceRecord < SourceRecord; end

    ActiveRecord::Base.establish_connection(:test)
  end
end
