module Stagehand
  module Connection
    def self.with_production_writes(&block)
      state = allow_unsynced_production_writes?
      allow_unsynced_production_writes!(true)
      return block.call
    ensure
      allow_unsynced_production_writes!(state)
    end

    def self.allow_unsynced_production_writes!(state = true)
      Thread.current[:stagehand_allow_unsynced_production_writes] = state
    end

    def self.allow_unsynced_production_writes?
      !!Thread.current[:stagehand_allow_unsynced_production_writes]
    end

    module AdapterExtensions
      def exec_insert(*)
        handle_readonly_writes!
        super
      end

      def exec_update(*)
        handle_readonly_writes!
        super
      end

      def exec_delete(*)
        handle_readonly_writes!
        super
      end

      private

      def write_access?
        Configuration.single_connection? || @config[:database] == Database.staging_database_name || Connection.allow_unsynced_production_writes?
      end

      def handle_readonly_writes!
        if write_access?
          return
        elsif Configuration.allow_unsynced_production_writes?
          Rails.logger.warn "Writing directly to #{@config[:database]} database using readonly connection"
        else
          raise(UnsyncedProductionWrite, "Attempted to write directly to #{@config[:database]} database using readonly connection")
        end
      end
    end
  end


  # EXCEPTIONS

  class UnsyncedProductionWrite < StandardError; end
end

ActiveRecord::Base.connection.class.prepend(Stagehand::Connection::AdapterExtensions)
