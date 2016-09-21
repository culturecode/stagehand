module Stagehand
  module Connection
    def self.with_production_writes(model, &block)
      state = model.connection.readonly?
      model.connection.readonly!(false)
      return block.call
    ensure
      model.connection.readonly!(state)
    end

    module AdapterExtensions
      def self.prepended(base)
        base.set_callback :checkout, :after, :update_readonly_state
        base.set_callback :checkin, :before, :clear_readonly_state
      end

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

      def allow_writes(&block)
        state = readonly?
        readonly!(true)
        return block.call
      ensure
        readonly!(state)
      end

      def readonly!(state = true)
        @readonly = state
      end

      def readonly?
        !!@readonly
      end

      private

      def update_readonly_state
        readonly! if @config[:database] == Database.production_database_name
      end

      def clear_readonly_state
        readonly!(false)
      end

      def handle_readonly_writes!
        if !readonly?
          return
        elsif Configuration.allow_unsynced_production_writes?
          puts "Writing directly to production database"
        else
          raise(ProductionWrite, "Attempted to write directly to production database")
        end
      end
    end
  end


  # EXCEPTIONS

  class ProductionWrite < StandardError; end
end

ActiveRecord::Base.connection.class.prepend(Stagehand::Connection::AdapterExtensions)
