namespace :stagehand do
  desc "Polls the commit entries table for changes to sync to production"
  task :auto_sync, [:delay] => :environment do |t, args|
    Stagehand::Staging::Synchronizer.auto_sync(args[:delay] ||= 5.seconds)
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
