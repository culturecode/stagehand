module Stagehand
  module Compatibility
    extend self

    def rails(min: nil, max: nil, less_than: nil, greater_than: nil)
      return unless Rails.version >= min.to_s if min
      return unless Rails.version <= max.to_s if max
      return unless Rails.version < less_than.to_s if less_than
      return unless Rails.version > greater_than.to_s if greater_than

      yield
    end
  end
end
