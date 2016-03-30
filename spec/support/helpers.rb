def in_ghost_mode(&block)
  context 'in ghost mode' do
    before { Rails.configuration.x.stagehand.ghost_mode = true }
    after { Rails.configuration.x.stagehand.ghost_mode = false }

    instance_exec(&block)
  end
end
