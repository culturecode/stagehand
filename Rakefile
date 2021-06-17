begin
  require 'bundler/setup'
rescue LoadError
  puts 'You must `gem install bundler` and `bundle install` to run rake tasks'
end

# While I am not sure, if rails' engine rake tasks are usuable with this app
# I leave the config in, but commented out
#
# APP_PATH = File.expand_path("spec/internal", __dir__)
# ENGINE_ROOT = File.expand_path("spec/internal", __dir__)
# APP_RAKEFILE = File.expand_path("spec/internal/Rakefile", __dir__)
# load 'rails/tasks/engine.rake'

load 'rails/tasks/statistics.rake'

Bundler::GemHelper.install_tasks


# Add Rspec tasks
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

task :default => :spec
