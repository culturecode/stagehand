RSpec.configure do |config|
  config.before(:suite) do
    Stagehand::Staging.connection_name = :staging
    Stagehand::Production.connection_name = :production

    # Create tables in the test and production database so we test copying from one to the other
    [Stagehand::Staging.connection_name, Stagehand::Production.connection_name].each do |connection_name|
      ActiveRecord::Base.establish_connection connection_name

      ActiveRecord::Schema.define do
        create_table :source_records, :force => true do |t|
          t.string :name
          t.timestamps :null => true
        end
      end
    end

    ActiveRecord::Base.establish_connection(Stagehand::Staging.connection_name)

    # Create the model
    class SourceRecord < ActiveRecord::Base; end

    # Add stagehand
    Stagehand::Schema.add_stagehand!
  end

  # Ensure changes to the connection_name are reset
  config.before do
    Stagehand::Staging.connection_name = :staging
    Stagehand::Production.connection_name = :production
  end
end
