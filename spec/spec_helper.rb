require 'bundler'
Bundler.require :default, :development

# If you're using all parts of Rails:
Combustion.initialize! :all
# Or, load just what you need:
# Combustion.initialize! :active_record, :action_controller

require 'stagehand'
