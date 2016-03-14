module Stagehand
  def self.configuration
    Configuration
  end

  module Configuration
    def self.staging_connection_name
      Rails.configuration.x.stagehand.staging_connection_name || raise(StagingConnectionNameNotSet)
    end

    def self.production_connection_name
      Rails.configuration.x.stagehand.production_connection_name || raise(ProductionConnectionNameNotSet)
    end

    def self.ghost_mode
      Rails.configuration.x.stagehand.ghost_mode
    end
  end

  # EXCEPTIONS
  class StagingConnectionNameNotSet < StandardError; end
  class ProductionConnectionNameNotSet < StandardError; end
end
