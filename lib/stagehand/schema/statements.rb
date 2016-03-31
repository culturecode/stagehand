module Stagehand
  module Schema
    module Statements
      # Ensure that developers are aware they need to make a determination of whether stagehand should track this table or not
      def create_table(table_name, options = {})
        case options.symbolize_keys[:stagehand]
        when true
          super
          Schema.add_stagehand! :only => table_name
        when false
          super
        else
          raise TableOptionNotSet, "If this table contains data to sync to the production database, pass #{{:stagehand => true}}" unless UNTRACKED_TABLES.include?(table_name)
          super
        end
      end
    end
  end

  # EXCEPTIONS
  class TableOptionNotSet < ActiveRecord::ActiveRecordError; end
end

ActiveRecord::Base.connection.class.include Stagehand::Schema::Statements
