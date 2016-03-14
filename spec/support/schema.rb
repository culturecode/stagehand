RSpec.configure do |config|
  config.before(:suite) do
    # Create tables in the test and production database so we test copying from one to the other
    [Stagehand.configuration.staging_connection_name, Stagehand.configuration.production_connection_name].each do |connection_name|
      ActiveRecord::Base.establish_connection connection_name

      ActiveRecord::Schema.define do
        create_table :source_records, :force => true do |t|
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
  end

  # Ensure changes to the connection_name are reset
  staging = Rails.configuration.x.stagehand.staging_connection_name
  production = Rails.configuration.x.stagehand.production_connection_name
  ghost_mode = Rails.configuration.x.stagehand.ghost_mode

  config.before do
    Rails.configuration.x.stagehand.staging_connection_name = staging
    Rails.configuration.x.stagehand.production_connection_name = production
    Rails.configuration.x.stagehand.ghost_mode = ghost_mode
  end
end
