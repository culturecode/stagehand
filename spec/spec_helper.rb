ENV['RAILS_ENV'] ||= 'test'

require 'bundler'
Bundler.require :default, :development

Combustion.initialize! :all do
  config.x.stagehand.production_connection_name = :production
end

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

require 'rspec/rails'

# Add additional requires below this line. Rails is not loaded until this point!

ENGINE_RAILS_ROOT = File.join(File.dirname(__FILE__), '../')
Dir[File.join(ENGINE_RAILS_ROOT, "spec/support/**/*.rb")].each {|f| require f }

RSpec.configure do |config|
  config.fixture_path = "#{::Rails.root}/spec/fixtures"

  config.append_after(:each) do
    DatabaseCleaner.strategy = :deletion
    DatabaseCleaner.clean

    Stagehand::Configuration.staging_model_tables = Set.new
  end
end
