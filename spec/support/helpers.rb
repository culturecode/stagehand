def in_ghost_mode(&block)
  context 'in ghost mode' do
    before { Rails.configuration.x.stagehand.ghost_mode = true }
    after { Rails.configuration.x.stagehand.ghost_mode = false }

    instance_exec(&block)
  end
end

def without_transactional_fixtures
  # Transactions hide changes from other connections. Disable transactional fixtures so it's easier to detect changes
  # across connections. In practice, this won't be an issue because connections will be modified at the beginning of
  # the controller action.
  before(:context) do
    self.use_transactional_fixtures = false
  end

  after(:context) do
    self.use_transactional_fixtures = true
  end
end
