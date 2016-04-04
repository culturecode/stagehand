module Stagehand
  extend self

  def configuration
    Configuration
  end

  module Configuration
    extend self

    def staging_connection_name
      Rails.configuration.x.stagehand.staging_connection_name || raise(StagingConnectionNameNotSet)
    end

    def production_connection_name
      Rails.configuration.x.stagehand.production_connection_name || raise(ProductionConnectionNameNotSet)
    end

    def ghost_mode?
      !!Rails.configuration.x.stagehand.ghost_mode
    end

    # Returns true if the production and staging connections are the same.
    # Use case: Front-end devs may not have a second database set up as they are only concerned with the front end
    def single_connection?
      staging_connection_name == production_connection_name
    end
  end

  # EXCEPTIONS
  class StagingConnectionNameNotSet < StandardError; end
  class ProductionConnectionNameNotSet < StandardError; end
end
