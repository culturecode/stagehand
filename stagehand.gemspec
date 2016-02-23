$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "stagehand/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "stagehand"
  s.version     = Stagehand::VERSION
  s.authors     = ["Nicholas Jakobsen"]
  s.email       = ["nicholas.jakobsen@gmail.com"]
  s.homepage    = "https://github.com/culturecode/stagehand"
  s.summary     = "Some summary"
  s.description = "Some description"
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]

  s.add_dependency "rails", "~> 4.2"
  s.add_dependency "mysql2"

  s.add_development_dependency "rspec-rails", "~> 3.0"
end
