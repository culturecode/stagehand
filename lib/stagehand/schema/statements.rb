module Stagehand
  module Schema
    module Statements
      # Ensure that developers are aware they need to make a determination of whether stagehand should track this table or not
      def create_table(table_name, options = {})
        super
        if options.symbolize_keys[:stagehand] && !UNTRACKED_TABLES.include?(table_name)
          Schema.add_stagehand! :only => table_name
        end
      end
    end
  end
end

ActiveRecord::Base.connection.class.include Stagehand::Schema::Statements
