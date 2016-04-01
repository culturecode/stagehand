module Stagehand
  module Schema
    module Statements
      # Ensure that developers are aware they need to make a determination of whether stagehand should track this table or not
      def create_table(table_name, options = {})
        super

        return if options.symbolize_keys[:stagehand] == false
        return if UNTRACKED_TABLES.include?(table_name)
        return if Database.connected_to_production?

        Schema.add_stagehand! :only => table_name
      end
    end
  end
end

ActiveRecord::Base.connection.class.include Stagehand::Schema::Statements
