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
      # @@semaphore.synchronize do
        begin
          different = current_connection_name != connection_name.to_sym

          if different
            ConnectionStack.push(connection_name.to_sym)
            Rails.logger.debug "Connecting to #{current_connection_name}"
            connect_to(current_connection_name)
          else
            Rails.logger.debug "Already connected to #{connection_name}"
          end

          yield connection_name
        ensure
          if different
            ConnectionStack.pop
            Rails.logger.debug "Restoring connection to #{current_connection_name}"
            connect_to(current_connection_name)
          end
        end
      # end
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
      ActiveRecord::Base.connection_specification_name = connection_name
    end

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

    class StagingProbe < ActiveRecord::Base
      self.abstract_class = true

      def self.init_connection
        establish_connection(name)
      end

      # Ensure the connection pool is named after the desired connection, not "StagingProbe"
      def self.name
        Configuration.staging_connection_name
      end

      init_connection
    end

    class ProductionProbe < ActiveRecord::Base
      self.abstract_class = true

      def self.init_connection
        establish_connection(name)
      end

      # Ensure the connection pool is named after the desired connection, not "ProductionProbe"
      def self.name
        Configuration.production_connection_name
      end

      init_connection
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
