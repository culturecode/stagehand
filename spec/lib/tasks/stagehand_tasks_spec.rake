require 'rake'
require 'rails_helper'

Rails.application.load_tasks
include Stagehand::Database

describe "Stagehand Tasks" do
  before do
    @my_migration_version = '1'
  end

  describe "stagehand:migration" do
    without_transactional_fixtures

    it 'should migrate both tables' do
      expect { Rake::Task['db:migrate'].invoke }.to change{ [production_database_versions.last, staging_database_version.last] }.to(["1", "1"])
    end

    it 'should rollback both tables' do
      Rake::Task['db:migrate']
      expect { Rake::Task['db:rollback'].invoke }.to change{ [production_database_versions.last, staging_database_version.last] }.to(["0", "0"])
    end
  end
end
