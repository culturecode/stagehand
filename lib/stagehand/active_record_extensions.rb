ActiveRecord::Base.class_eval do
  # SYNC CALLBACKS
  define_model_callbacks :sync, :sync_as_subject, :sync_as_affected

  # SYNC STATUS
  def self.inherited(subclass)
    super

    subclass.class_eval do
      has_one :stagehand_unsynced_indicator,
        lambda { where(:stagehand_commit_entries => {:table_name => subclass.table_name}).readonly },
        :class_name => Stagehand::Staging::CommitEntry,
        :foreign_key => :record_id

      def synced?
        stagehand_unsynced_indicator.blank?
      end
    end
  end

  # SCHEMA
  delegate :has_stagehand?, to: :class
  def self.has_stagehand?
    @has_stagehand = Stagehand::Schema.has_stagehand?(table_name) unless defined?(@has_stagehand)
    return @has_stagehand
  end
end
