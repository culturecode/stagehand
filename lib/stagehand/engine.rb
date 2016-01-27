module Stagehand
  class Engine < ::Rails::Engine
    isolate_namespace Stagehand

    config.generators do |g|
      g.test_framework :rspec
    end
  end
end
