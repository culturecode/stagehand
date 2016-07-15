module Stagehand
  module Database
    extend self

    @@connection_name_stack = [Rails.env.to_sym]

    def each(&block)
      with_connection(Configuration.staging_connection_name, &block)
      with_connection(Configuration.production_connection_name, &block) unless Configuration.single_connection?
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

    def with_connection(connection_name)
      different = current_connection_name != connection_name.to_sym

      @@connection_name_stack.push(connection_name.to_sym)
      Rails.logger.debug "Connecting to #{current_connection_name}"
      connect_to(current_connection_name) if different

      yield connection_name
    ensure
      @@connection_name_stack.pop
      Rails.logger.debug "Restoring connection to #{current_connection_name}"
      connect_to(current_connection_name) if different
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
