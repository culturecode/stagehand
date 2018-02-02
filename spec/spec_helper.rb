require 'bundler'
Bundler.require :default, :development

Combustion.initialize! :all do
  config.x.stagehand.production_connection_name = :production
end

require 'stagehand'
