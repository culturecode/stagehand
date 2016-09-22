module Stagehand
  module Database
    extend self

    @@connection_name_stack = [Rails.env.to_sym]

    def each(&block)
      with_staging_connection(&block)
      with_production_connection(&block) unless Configuration.single_connection?
    end

    def connected_to_production?
      current_connection_name == Configuration.production_connection_name
    end

    def connected_to_staging?
      current_connection_name == Configuration.staging_connection_name
    end

    def production_connection
      ProductionProbe.connection
    end

    def staging_connection
      StagingProbe.connection
    end

    def production_database_name
      database_name(Configuration.production_connection_name)
    end

    def staging_database_name
      database_name(Configuration.staging_connection_name)
    end

    def staging_database_versions
      Stagehand::Database.staging_connection.select_values(versions_scope)
    end

    def production_database_versions
      Stagehand::Database.production_connection.select_values(versions_scope)
    end

    def with_staging_connection(&block)
      with_connection(Configuration.staging_connection_name, &block)
    end

    def with_production_connection(&block)
      with_connection(Configuration.production_connection_name, &block)
    end

    def with_connection(connection_name)
      different = current_connection_name != connection_name.to_sym

      if different
        @@connection_name_stack.push(connection_name.to_sym)
        Rails.logger.debug "Connecting to #{current_connection_name}"
        connect_to(current_connection_name)
      end

      yield connection_name
    ensure
      if different
        @@connection_name_stack.pop
        Rails.logger.debug "Restoring connection to #{current_connection_name}"
        connect_to(current_connection_name)
      end
    end

    def transaction
      success = false
      output = nil
      ActiveRecord::Base.transaction do
        Production::Record.transaction do
          output = yield
          success = true
        end
        raise ActiveRecord::Rollback unless success
      end
      return output
    end

    private

    def connect_to(connection_name)
      ActiveRecord::Base.establish_connection(connection_name)
    end

    def current_connection_name
      @@connection_name_stack.last
    end

    def database_name(connection_name)
      Rails.configuration.database_configuration[connection_name.to_s]['database']
    end

    def versions_scope
      ActiveRecord::SchemaMigration.order(:version)
    end

    # CLASSES

    class StagingProbe < ActiveRecord::Base
      self.abstract_class = true

      def self.init_connection
        establish_connection(Configuration.staging_connection_name)
      end

      init_connection
    end

    class ProductionProbe < ActiveRecord::Base
      self.abstract_class = true

      def self.init_connection
        establish_connection(Configuration.production_connection_name)
      end

      init_connection
    end
  end
end
