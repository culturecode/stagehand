require 'rails_helper'

describe 'Stagehand::Staging::Controller', :type => :controller do
  before { ActiveRecord::Base.establish_connection(Stagehand::Production.connection_name) }
  let(:staging) { Stagehand::Staging.connection_name }
  let(:production) { Stagehand::Production.connection_name }

  describe '::included' do
    controller do
      include Stagehand::Staging::Controller

      def index
        SourceRecord.create
        render :nothing => true
      end
    end

    it 'performs all queries on the staging database' do
      expect { get :index }.to change { Probe.count(staging, 'source_records') }.by(1)
    end

    it 'only has an effect for the duration of the action' do
      get :index
      expect { SourceRecord.create }.not_to change { Probe.count(staging, 'source_records') }
    end

    it 'resets the connection to the production database after the action' do
      expect do
        SourceRecord.create
        get :index
        SourceRecord.create
      end.to change { Probe.count(production, 'source_records') }.by(2)
    end


    it 'does not affect the connection of models that have specifically called establish_connection' do
      SourceRecord.establish_connection(Stagehand::Production.connection_name)
      expect { get :index }.not_to change { Probe.count(staging, 'source_records') }
      SourceRecord.remove_connection
    end

    it 'once again affects the connection of models that have had their connection removed' do
      SourceRecord.establish_connection(Stagehand::Production.connection_name)
      SourceRecord.remove_connection
      expect { get :index }.to change { Probe.count(staging, 'source_records') }.by(1)
    end
  end


  # HELPERS

  class Probe < ActiveRecord::Base
    def self.count(connection_name, table_name)
      establish_connection(connection_name)
      self.table_name = SourceRecord.table_name
      super()
    end
  end
end
