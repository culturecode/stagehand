require 'rake'

Rails.application.load_tasks

describe "Stagehand Tasks" do
  describe "stagehand:migration" do
    without_transactional_fixtures

    it 'should migrate both tables' do
      expect { Rake::Task['db:migrate'].invoke }.to change{ find_database_versions }.to(["1", "1"])
    end

    it 'should rollback both tables' do
      Rake::Task['db:migrate']
      expect { Rake::Task['db:rollback'].invoke }.to change{ find_database_versions }.to(["0", "0"])
    end

    def find_database_versions
      [Stagehand::Database.production_database_versions.last, Stagehand::Database.staging_database_versions.last]
    end
  end
end
