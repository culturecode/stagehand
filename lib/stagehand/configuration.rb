module Stagehand
  extend self

  def configuration
    yield Configuration if block_given?
    Configuration
  end

  module Configuration
    extend self

    mattr_accessor :checklist_confirmation_filter, :checklist_association_filter, :checklist_relation_filter, :ignored_columns
    self.ignored_columns = HashWithIndifferentAccess.new

    def staging_connection_name
      Rails.env.to_sym
    end

    def production_connection_name
      Rails.configuration.x.stagehand.production_connection_name || Rails.env.to_sym
    end

    def ghost_mode?
      !!Rails.configuration.x.stagehand.ghost_mode
    end

    # Allow unsynchronized writes directly to the production database? A warning will be logged if set to true.
    def allow_unsynced_production_writes?
      !!Rails.configuration.x.stagehand.allow_unsynced_production_writes
    end

    # Returns true if the production and staging connections are the same.
    # Use case: Front-end devs may not have a second database set up as they are only concerned with the front end
    def single_connection?
      staging_connection_name == production_connection_name
    end

    # Columns not to copy to the production database
    # e.g. table_name => [column, column, ...]
    def self.ignored_columns=(hash)
      super HashWithIndifferentAccess.new(hash)
    end
  end
end
