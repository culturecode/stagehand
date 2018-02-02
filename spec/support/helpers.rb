def allow_unsynced_production_writes
  use_configuration :allow_unsynced_production_writes => true
end

def in_ghost_mode(&block)
  context 'in ghost mode' do
    use_configuration(:ghost_mode => true)
    instance_exec(&block)
  end
end

def use_configuration(new_configuration)
  around do |example|
    with_configuration(new_configuration) do
      example.run
    end
  end
end

def with_configuration(new_configuration, &block)
  old_configuration = set_configuration(new_configuration)
  block.call rescue nil
  set_configuration(old_configuration)
end

def set_configuration(new_configuration)
  {}.tap do |old_configuration|
    new_configuration.each do |option, value|
      old_configuration[option] = Rails.configuration.x.stagehand.send("#{option}")
      Rails.configuration.x.stagehand.send("#{option}=", value)
    end

    Stagehand::Database::ProductionProbe.init_connection
    Stagehand::Database::StagingProbe.init_connection
  end
end

def without_transactional_fixtures
  # Transactions hide changes from other connections. Disable transactional fixtures so it's easier to detect changes
  # across connections. In practice, this won't be an issue because connections will be modified at the beginning of
  # the controller action.
  before(:context) do
    Stagehand::Compatibility.rails(less_than: 5) do
      config.use_transactional_fixtures = true
    end
    Stagehand::Compatibility.rails(min: 5) do
      binding.pry

      config.use_transactional_tests = true
    end
  end

  after(:context) do
    tables = ActiveRecord::Base.connection.tables
    tables -= ['schema_migrations']
    tables.each do |table_name|
      ActiveRecord::Base.connection.execute("DELETE FROM #{table_name}")
    end
    Stagehand::Compatibility.rails(less_than: 5) do
      config.use_transactional_fixtures = true
    end
    Stagehand::Compatibility.rails(min: 5) do
      config.use_transactional_tests = true
    end
  end
end
