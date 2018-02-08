require 'thread'

module Stagehand
  module Database
    extend self

    def each(&block)
      with_production_connection(&block) unless Configuration.single_connection?
      with_staging_connection(&block)
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
        ConnectionStack.push(connection_name.to_sym)
        Rails.logger.debug "Connecting to #{current_connection_name}"
        ActiveRecord::Base.connection_specification_name = current_connection_name
      else
        Rails.logger.debug "Already connected to #{connection_name}"
      end

      yield connection_name
    ensure
      if different
        ConnectionStack.pop
        Rails.logger.debug "Restoring connection to #{current_connection_name}"
        ActiveRecord::Base.connection_specification_name = current_connection_name
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

    def current_connection_name
      ConnectionStack.last
    end

    def database_name(connection_name)
      Rails.configuration.database_configuration[connection_name.to_s]['database']
    end

    def versions_scope
      ActiveRecord::SchemaMigration.order(:version)
    end

    # CLASSES

    class Probe < ActiveRecord::Base
      self.abstract_class = true

      # We fake the class name so we can create a connection pool with the desired connection name instead of the name of the class
      def self.init_connection(connection_name)
        @probe_name = connection_name
        establish_connection(connection_name)
      ensure
        @probe_name = nil
      end

      def self.name
        @probe_name || super
      end
    end

    class StagingProbe < Probe
      self.abstract_class = true

      def self.init_connection
        super(Configuration.staging_connection_name)
      end

      init_connection
    end

    class ProductionProbe < Probe
      self.abstract_class = true

      def self.init_connection
        super(Configuration.production_connection_name)
      end

      init_connection unless Configuration.single_connection?
    end

    # Threadsafe tracking of the connection stack
    module ConnectionStack
      @@connection_name_stack = Hash.new { |h,k| h[k] = [ Rails.env.to_sym ] }

      def self.push(connection_name)
        current_stack.push connection_name
      end

      def self.pop
        current_stack.pop
      end

      def self.last
        current_stack.last
      end

      def self.current_stack
        @@connection_name_stack[Thread.current.object_id]
      end
    end
  end
end
