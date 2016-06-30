require 'rake'
require 'rails_helper'

Rails.application.load_tasks

describe "Stagehand Tasks" do
  before do
    @my_migration_version = '1'
  end

  describe "stagehand:migration" do
    without_transactional_fixtures

    it 'should migrate both tables' do
      expect { Rake::Task['db:migrate'].invoke }
          .to change{ [Stagehand::Database.production_database_versions.last, Stagehand::Database.staging_database_versions.last] }
            .to(["1", "1"])
    end

    it 'should rollback both tables' do
      Rake::Task['db:migrate']
      expect { Rake::Task['db:rollback'].invoke }
          .to change{ [Stagehand::Database.production_database_versions.last, Stagehand::Database.staging_database_versions.last] }
            .to(["0", "0"])
    end
  end
end
