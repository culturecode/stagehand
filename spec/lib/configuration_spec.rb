require 'rails_helper'

describe Stagehand::Configuration do
  describe 'production_connection_name' do
    around do |example|
      name = Rails.configuration.x.stagehand.production_connection_name
      example.run
      Rails.configuration.x.stagehand.production_connection_name = name
    end

    it 'returns the value from the Rails custom configuration variable stagehand.production_connection_name' do
      expect { Rails.configuration.x.stagehand.production_connection_name = :bob }
        .to change { subject.production_connection_name }.to(:bob)
    end

    it 'defaults to the database.yml connection for the current Rails.env' do
      Rails.configuration.x.stagehand.production_connection_name = :bob
      expect { Rails.configuration.x.stagehand.production_connection_name = nil }
        .to change { subject.production_connection_name }.to(:test)
    end
  end

  describe 'staging_connection_name' do
    it 'cannot be changed' do
      expect { Rails.configuration.x.stagehand.staging_connection_name = :bob }
        .not_to change { subject.staging_connection_name }
    end

    it 'returns the Rails.env name as a symbol' do
      expect(subject.staging_connection_name).to eq(Rails.env.to_sym)
    end
  end

  describe '::ghost_mode?' do
    after { Rails.configuration.x.stagehand.ghost_mode = false }

    it 'is set using the Rails custom configuration variable stagehand.ghost_mode' do
      expect { Rails.configuration.x.stagehand.ghost_mode = 'test' }.to change { subject.ghost_mode? }.to(true)
    end
  end
end
