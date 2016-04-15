namespace :stagehand do
  desc "Polls the commit entries table for changes to sync to production"
  task :auto_sync, [:delay] => :environment do |t, args|
    Stagehand::Staging::Synchronizer.auto_sync(args[:delay] ||= 5.seconds)
  end

  desc "Syncs records that don't need confirmation to production"
  task :sync, [:limit] => :environment do |t, args|
    Stagehand::Staging::Synchronizer.sync(args[:limit])
  end

  desc "Syncs all records to production, including those that require confirmation"
  task :sync_all, :environment do
    Stagehand::Staging::Synchronizer.sync_all
  end

  desc "Migrate both databases used by stagehand"
  task :migrate => :environment do
    [Rails.configuration.x.stagehand.staging_connection_name,
     Rails.configuration.x.stagehand.production_connection_name].each do |config_key|
      puts "Migrating #{config_key}"
      ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[config_key.to_s])
      ActiveRecord::Migrator.migrate('db/migrate')
    end
  end
end

# Enhance the regular db:migrate task to run the stagehand migration task so both stagehand databases are migrated
Rake::Task['db:migrate'].enhance(['stagehand:migrate'])
