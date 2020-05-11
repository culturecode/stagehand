describe Stagehand::Staging::Model do
  let(:klass) do
    Object.send(:remove_const, :Klass) if Object.const_defined?(:Klass)
    Klass = Class.new(SourceRecord)
  end

  context 'when included in a model' do
    let(:staging) { Rails.configuration.database_configuration[Stagehand.configuration.staging_connection_name.to_s] }

    it 'establishes a connection to the staging database' do
      klass.connection_specification_name = Stagehand.configuration.production_connection_name
      expect { klass.include(subject) }.to change { klass.connection.current_database }.to(staging['database'])
    end

    it 'prefixes the table name with the database name when the current connection is production' do
      klass.include(subject)

      Stagehand::Database.with_production_connection do
        expect(klass.all.to_sql).to include("FROM `#{klass.connection.current_database}`.`#{klass.table_name}`")
      end
    end

    it 'does not prefix the table name with the database name when the current connection is staging' do
      klass.include(subject)

      Stagehand::Database.with_staging_connection do
        expect(klass.all.to_sql).not_to include("FROM `#{klass.connection.current_database}`.`#{klass.table_name}`")
      end
    end

    it 'does not get written if part of a failed transaction' do
      klass.include(subject)
      Stagehand::Database.with_staging_connection do
        expect do
          ActiveRecord::Base.transaction { Klass.create; raise(ActiveRecord::Rollback) }
        end.not_to change { Klass.count }
      end
    end

    in_ghost_mode do
      it 'does not change the connection' do
        klass.connection_specification_name = Stagehand.configuration.production_connection_name
        expect { klass.include(subject) }.not_to change { klass.connection.current_database }
      end
    end
  end
end
