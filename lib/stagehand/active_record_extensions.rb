ActiveRecord::Base.class_eval do
  # SYNC CALLBACKS
  define_callbacks :sync

  def self.before_sync(method, options = {})
    set_callback :sync, :before, method, options
  end

  def self.after_sync(method, options = {})
    set_callback :sync, :after, method, options
  end

  # SYNC STATUS
  def self.inherited(subclass)
    super

    subclass.class_eval do
      has_many :stagehand_commit_entries,
        lambda { where(:stagehand_commit_entries => {:table_name => subclass.table_name}) },
        :class_name => Stagehand::Staging::CommitEntry,
        :foreign_key => :record_id

      def stagehand_synced?(options = {})
        if options[:only_contained]
          stagehand_commit_entries.contained.blank?
        else
          stagehand_commit_entries.blank?
        end
      end
    end
  end
end
