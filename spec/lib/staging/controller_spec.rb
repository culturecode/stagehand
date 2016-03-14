require 'rails_helper'

describe 'Stagehand::Staging::Controller', :type => :controller do
  let(:staging) { Stagehand.configuration.staging_connection_name }
  let(:production) { Stagehand.configuration.production_connection_name }
  around {|example| Stagehand::Database.connect_to_database(production) { example.run } }

  context 'when included' do
    controller do
      # Simulate inheriting production database connection from superclass
      around_action :use_production_database,     :if => proc {|c| c.params[:use_production_callback] }
      around_action :preceeding_callback,          :if => proc {|c| c.params[:preceeding_callback] }

      include Stagehand::Staging::Controller

      around_action :subsequent_callback,         :if => proc {|c| c.params[:subsequent_callback] }
      skip_action_callback :use_staging_database, :if => proc {|c| c.params[:skip_staging_callback] }

      def index
        SourceRecord.create; render :nothing => true
      end

      def preceeding_callback
        SourceRecord.create; yield
      end

      def subsequent_callback
        SourceRecord.create; yield
      end
    end

    it 'performs all queries on the staging database' do
      expect { get :index }.to change { StagingSourceRecord.count }.by(1)
    end

    it 'only has an effect for the duration of the action' do
      get :index
      expect { SourceRecord.create }.not_to change { StagingSourceRecord.count }
    end

    it 'resets the connection to the previous database after the action' do
      expect do
        SourceRecord.create
        get :index
        SourceRecord.create
      end.to change { SourceRecord.count }.by(2)
    end

    it 'does not affect the connection of models that have specifically called establish_connection' do
      SourceRecord.establish_connection(production)
      expect { get :index }.not_to change { StagingSourceRecord.count }
      SourceRecord.remove_connection
    end

    it 'once again affects the connection of models that have had their connection removed' do
      SourceRecord.establish_connection(production)
      SourceRecord.remove_connection
      expect { get :index }.to change { StagingSourceRecord.count }.by(1)
    end

    it 'skipping the use_staging_database callback disable the database connection behaviour' do
      expect { get :index, :skip_staging_callback => true }.not_to change { StagingSourceRecord.count }
    end

    it 'can be used to override the behaviour of use_production_database' do
      expect { get :index, :use_production_callback => true }.to change { StagingSourceRecord.count }.by(1)
    end

    it 'enables the database connection behaviour before preceeding around filters are run' do
      expect { get :index, :preceeding_callback => true }.to change { StagingSourceRecord.count }.by(2)
    end

    it 'enables the database connection behaviour before subsequent around filters are run' do
      expect { get :index, :subsequent_callback => true }.to change { StagingSourceRecord.count }.by(2)
    end

    context 'in ghost mode' do
      before { Rails.configuration.x.stagehand.ghost_mode = true }

      it 'disables connection swapping' do
        expect do
          SourceRecord.create
          get :index
          SourceRecord.create
        end.to change { SourceRecord.count }.by(3)
      end
    end
  end


  # CONTEXT SETUP

  # Transactions hide changes from other connections. Disable transactional fixtures so it's easier to detect changes
  # across connections. In practice, this won't be an issue because connections will be modified at the beginning of
  # the controller action.
  before(:context) do
    self.use_transactional_fixtures = false
  end

  after(:context) do
    self.use_transactional_fixtures = true
  end


  # HELPERS

  class Probe < ActiveRecord::Base; end

  class StagingSourceRecord
    def self.count
      Probe.establish_connection(:staging)
      Probe.connection.select_value("SELECT count(id) FROM source_records").to_i
    end
  end

  class ProductionSourceRecord
    def self.count
      Probe.establish_connection(:production)
      Probe.connection.select_value("SELECT count(id) FROM source_records").to_i
    end
  end
end
