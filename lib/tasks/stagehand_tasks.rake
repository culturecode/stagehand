namespace :stagehand do
  desc "Explaining what the task does"
  task :auto_sync, [:delay] => :environment do |t, args|
    Stagehand::Staging::Synchronizer.auto_sync(args[:delay] ||= 5.seconds)
  end
end
