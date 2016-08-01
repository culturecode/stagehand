require 'rails_helper'

describe Stagehand::Database do
  let(:staging) { Stagehand.configuration.staging_connection_name }
  let(:production) { Stagehand.configuration.production_connection_name }

  describe '::with_connection' do
    it 'restores the database connection specified in the Rails environment after the given block' do
      expect { subject.with_connection(production) {} }.not_to change { ActiveRecord::Base.connection.current_database }
    end

    it 'sets and restores the correct database connections after nested blocks' do
      subject.with_connection(production) do
        outer_db = ActiveRecord::Base.connection.current_database

        subject.with_connection(staging) do
          expect(ActiveRecord::Base.connection.current_database).not_to eq(outer_db)
        end

        expect(ActiveRecord::Base.connection.current_database).to eq(outer_db)
      end
    end

    it 'does not reconnect if already connected to the desired database' do
      subject.with_connection(production) do
        connection = ActiveRecord::Base.connection
        subject.with_connection(production) do
          expect(connection.object_id).to eq(ActiveRecord::Base.connection.object_id)
        end
      end
    end
  end

  describe '::staging_connection' do
    without_transactional_fixtures

    before { SourceRecord.establish_connection(staging) }
    after { SourceRecord.remove_connection }

    it 'returns a connection object that uses the staging database' do
      expect { SourceRecord.create }.to change { subject.staging_connection.select_values(SourceRecord.all) }
    end

    it 'ignores the effects of a `with_connection` block connected to a different database' do
      subject.with_connection(production) do
        expect { SourceRecord.create }.to change { subject.staging_connection.select_values(SourceRecord.all) }
      end
    end
  end

  describe '::production_connection' do
    without_transactional_fixtures

    before { SourceRecord.establish_connection(production) }
    after { SourceRecord.remove_connection }

    it 'returns a connection object that uses the staging database' do
      expect { SourceRecord.create }.to change { subject.production_connection.select_values(SourceRecord.all) }
    end

    it 'ignores the effects of a `with_connection` block connected to a different database' do
      subject.with_connection(staging) do
        expect { SourceRecord.create }.to change { subject.production_connection.select_values(SourceRecord.all) }
      end
    end
  end

  describe '::transaction' do
    it 'rolls back changes in the staging database on exception' do
      expect { subject.transaction { SourceRecord.create; raise } rescue nil }
        .not_to change { SourceRecord.count }
    end

    it 'rolls back changes in the staging database on ActiveRecord::Rollback' do
      expect { subject.transaction { SourceRecord.create; raise ActiveRecord::Rollback } rescue nil }
        .not_to change { SourceRecord.count }
    end

    it 'rolls back changes in the production database on exception' do
      record = SourceRecord.create

      expect { subject.transaction { Stagehand::Production.save(record); raise } rescue nil }
        .not_to change { Stagehand::Production.status(record) }
    end

    it 'rolls back changes in the production database on ActiveRecord::Rollback' do
      record = SourceRecord.create

      expect { subject.transaction { Stagehand::Production.save(record); raise ActiveRecord::Rollback } rescue nil }
        .not_to change { Stagehand::Production.status(record) }
    end
  end
end
