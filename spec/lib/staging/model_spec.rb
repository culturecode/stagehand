require 'rails_helper'

describe Stagehand::Staging::Model do
  let(:klass) do
    Object.send(:remove_const, :Klass) if Object.const_defined?(:Klass)
    Klass = Class.new(SourceRecord)
  end

  context 'when included in a model' do
    before { klass.establish_connection(Stagehand.configuration.production_connection_name) }
    let(:staging) { Rails.configuration.database_configuration[Stagehand.configuration.staging_connection_name.to_s] }

    it 'establishes a connection to the staging database' do
      expect { klass.include(subject) }.to change { klass.connection.current_database }.to(staging['database'])
    end

    in_ghost_mode do
      it 'does not change the connection' do
        expect { klass.include(subject) }.not_to change { klass.connection.current_database }
      end
    end
  end
end
