RSpec.configure do |config|
  config.before(:suite) do
    Stagehand::Staging.environment = :staging
    Stagehand::Production.environment = :production

    # Create tables in the test and production database so we test copying from one to the other
    [Stagehand::Staging.environment, Stagehand::Production.environment].each do |connection_name|
      ActiveRecord::Base.establish_connection connection_name

      ActiveRecord::Schema.define do
        create_table :source_records, :force => true do |t|
          t.string :name
          t.timestamps :null => true
        end
      end
    end

    ActiveRecord::Base.establish_connection(Stagehand::Staging.environment)

    # Create the model
    class SourceRecord < ActiveRecord::Base; end

    # Add stagehand
    Stagehand::Schema.add_stagehand!
  end

  # Ensure changes to the environment are reset
  config.before do
    Stagehand::Staging.environment = :staging
    Stagehand::Production.environment = :production
  end
end
