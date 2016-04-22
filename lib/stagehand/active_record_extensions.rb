ActiveRecord::Base.class_eval do
  # SYNC CALLBACK
  define_callbacks :sync

  def self.before_sync(method, options = {})
    set_callback :sync, :before, method, options
  end

  def self.after_sync(method, options = {})
    set_callback :sync, :after, method, options
  end
end
