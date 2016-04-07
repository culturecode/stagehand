module Stagehand
  module Cache
    def cache(key, &block)
      @cache ||= {}
      if @cache.key?(key)
        @cache[key]
      else
        @cache[key] = block.call
      end
    end
  end
end
