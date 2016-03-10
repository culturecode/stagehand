module Stagehand
  class Engine < ::Rails::Engine
    isolate_namespace Stagehand

    config.generators do |g|
      g.test_framework :rspec
    end

    initializer "stagehand.set_connection_names" do
      Stagehand::Staging::connection_name = Rails.configuration.x.stagehand.staging_connection_name
      Stagehand::Production::connection_name = Rails.configuration.x.stagehand.production_connection_name
    end
  end
end
