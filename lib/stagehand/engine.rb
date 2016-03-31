module Stagehand
  class Engine < ::Rails::Engine
    isolate_namespace Stagehand

    config.generators do |g|
      g.test_framework :rspec
    end

    # These require the rails application to be intialized because configuration variables are used
    initializer "stagehand.load_modules" do
      require "stagehand/configuration"
      require "stagehand/controller_extensions"
      require "stagehand/staging"
      require "stagehand/schema"
      require "stagehand/production"
      require "stagehand/helpers"
    end
  end
end
