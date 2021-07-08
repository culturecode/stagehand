describe Stagehand::Staging::Model do
  let(:klass) do
    Object.send(:remove_const, :Klass) if Object.const_defined?(:Klass)
    Klass = Class.new(SourceRecord)
  end

  let(:staging) { Rails.configuration.database_configuration[Stagehand.configuration.staging_connection_name.to_s] }

  it 'establishes a connection to the staging database when included in a model' do
    klass.connection_specification_name = Stagehand.configuration.production_connection_name
    expect { klass.include(subject) }.to change { klass.connection.current_database }.to(staging['database'])
  end

  in_ghost_mode do
    it 'does not change the connection when included in a model' do
      klass.connection_specification_name = Stagehand.configuration.production_connection_name
      expect { klass.include(subject) }.not_to change { klass.connection.current_database }
    end
  end

  context 'when included in a model' do
    before do
      klass.include(subject)
    end

    it 'prefixes the table name with the database name when the current connection is production' do
      Stagehand::Database.with_production_connection do
        expect(klass.all.to_sql).to include("FROM `#{klass.connection.current_database}`.`#{klass.table_name}`")
      end
    end

    it 'prefixes the table name when connected to production after performing queries on the staging connection' do
      Stagehand::Database.with_staging_connection do
        klass.all.to_a
      end

      Stagehand::Database.with_production_connection do
        expect(klass.all.to_sql).to include("FROM `#{klass.connection.current_database}`.`#{klass.table_name}`")
      end
    end

    it 'does not prefix the table name with the database name when the current connection is staging' do
      Stagehand::Database.with_staging_connection do
        expect(klass.all.to_sql).not_to include("FROM `#{klass.connection.current_database}`.`#{klass.table_name}`")
      end
    end

    it 'does not prefix the table name with the database name when allow_unsynced_production_writes is true' do
      Stagehand::Database.with_production_connection do
        Stagehand::Connection.with_production_writes do
          expect(klass.all.to_sql).not_to include("FROM `#{klass.connection.current_database}`.`#{klass.table_name}`")
        end
      end
    end

    describe '::quoted_table_name' do
      it 'prefixes the table name when connected to production after being called while on the staging connection' do
        prefix = "`#{klass.connection.current_database}`"

        Stagehand::Database.with_staging_connection do
          klass.quoted_table_name
        end

        Stagehand::Database.with_production_connection do
          expect(klass.quoted_table_name).to start_with(prefix)
        end
      end

      it 'does not prefix the table name when connected to staging after being called while on the production connection' do
        prefix = "`#{klass.connection.current_database}`"

        Stagehand::Database.with_production_connection do
          klass.quoted_table_name
        end

        Stagehand::Database.with_staging_connection do
          expect(klass.quoted_table_name).not_to start_with(prefix)
        end
      end
    end

    it 'does not get written if part of a failed transaction' do
      Stagehand::Database.with_staging_connection do
        expect do
          ActiveRecord::Base.transaction { Klass.create; raise(ActiveRecord::Rollback) }
        end.not_to change { Klass.count }
      end
    end
  end
end
