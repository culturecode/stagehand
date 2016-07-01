namespace :stagehand do
  desc "Polls the commit entries table for changes to sync to production"
  task :auto_sync, [:delay] => :environment do |t, args|
    Stagehand::Staging::Synchronizer.auto_sync(args[:delay] ||= 5.seconds)
  end

  desc "Syncs records that don't need confirmation to production"
  task :sync, [:limit] => :environment do |t, args|
    limit = args[:limit].present? ? args[:limit].to_i : nil
    Stagehand::Staging::Synchronizer.sync(limit)
  end

  desc "Syncs all records to production, including those that require confirmation"
  task :sync_all => :environment do
    Stagehand::Staging::Synchronizer.sync_all
  end

  desc "Migrate both databases used by stagehand"
  task :migrate => :environment do
    run_on_both_databases do
      Rake::Task['db:migrate'].reenable
      Rake::Task['db:migrate'].invoke
    end
    Rake::Task['db:migrate'].clear
  end

  desc "Rollback both databases used by stagehand"
  task :rollback => :environment do
    run_on_both_databases do
      Rake::Task['db:rollback'].reenable
      Rake::Task['db:rollback'].invoke
    end
    Rake::Task['db:rollback'].clear
  end
end

def run_on_both_databases(&block)
  connections = [Stagehand.configuration.staging_connection_name, Stagehand.configuration.production_connection_name]
  connections.compact.uniq.each do |connection_name|
    puts "#{connection_name}"
    Stagehand::Database.with_connection(connection_name, &block)
  end
end

# Enhance the regular db:migrate/db:rollback tasks to run the stagehand migration/rollback tasks so both stagehand databases are migrated
Rake::Task['db:migrate'].enhance(['stagehand:migrate'])
Rake::Task['db:rollback'].enhance(['stagehand:rollback'])
