require 'rails_helper'

describe Stagehand::Database do
  let(:staging) { Stagehand.configuration.staging_connection_name }
  let(:production) { Stagehand.configuration.production_connection_name }

  describe '::connect_to_database' do
    it 'restores the database connection specified in the Rails environment after the given block' do
      expect { subject.connect_to_database(production) {} }.not_to change { ActiveRecord::Base.connection.current_database }
    end

    it 'sets and restores the correct database connections after nested blocks' do
      subject.connect_to_database(production) do
        outer_db = ActiveRecord::Base.connection.current_database

        subject.connect_to_database(staging) do
          expect(ActiveRecord::Base.connection.current_database).not_to eq(outer_db)
        end

        expect(ActiveRecord::Base.connection.current_database).to eq(outer_db)
      end
    end

    it 'does not reconnect if already connected to the desired database' do
      subject.connect_to_database(production) do
        connection = ActiveRecord::Base.connection
        subject.connect_to_database(production) do
          expect(connection.object_id).to eq(ActiveRecord::Base.connection.object_id)
        end
      end
    end
  end
end
