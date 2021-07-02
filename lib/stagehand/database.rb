require 'thread'
require 'stagehand/active_record_extensions'

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

    def with_connection(connection_name, &block)
      if current_connection_name != connection_name.to_sym
        Rails.logger.debug "Connecting to #{connection_name}"
        output = swap_connection(connection_name, &block)
        Rails.logger.debug "Restoring connection to #{current_connection_name}"
      else
        Rails.logger.debug "Already connected to #{connection_name}"
        output = yield connection_name
      end
      return output
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

    def swap_connection(connection_name)
      cache = ActiveRecord::Base.connection_pool.query_cache_enabled
      ConnectionStack.push(connection_name.to_sym)
      ActiveRecord::Base.connection_specification_name = current_connection_name
      ActiveRecord::Base.connection_pool.enable_query_cache! if cache

      yield connection_name
    ensure
      ConnectionStack.pop
      ActiveRecord::Base.connection_specification_name = current_connection_name
      ActiveRecord::Base.connection_pool.enable_query_cache! if cache
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

    class Probe < ActiveRecord::Base
      self.abstract_class = true
      self.stagehand_threadsafe_connections = false # We don't want to track connection per-thread for Probes

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

      def self.connection
        if Stagehand::Database.connected_to_staging?
          ActiveRecord::Base.connection # Reuse existing connection so we stay within the current transaction
        else
          super
        end
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
        if stack = Thread.current.thread_variable_get('sparkle_connection_name_stack')
          stack
        else
          stack = Concurrent::Array.new
          stack << Rails.env.to_sym
          Thread.current.thread_variable_set('sparkle_connection_name_stack', stack)
          stack
        end
      end
    end
  end
end
