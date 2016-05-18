module Stagehand
  module Schema
    module Statements
      # Ensure that developers are aware they need to make a determination of whether stagehand should track this table or not
      def create_table(table_name, options = {})
        super

        return if options.symbolize_keys[:stagehand] == false
        return if UNTRACKED_TABLES.include?(table_name)
        return if Database.connected_to_production? && !Stagehand::Configuration.single_connection?

        Schema.add_stagehand! :only => table_name
      end

      def rename_table(old_table_name, new_table_name, *)
        Schema.remove_stagehand!(:only => old_table_name)
        super
        Schema.add_stagehand!(:only => new_table_name)
        Staging::CommitEntry.where(:table_name => old_table_name).update_all(:table_name => new_table_name)
      end
    end
  end
end

ActiveRecord::Base.connection.class.include Stagehand::Schema::Statements
