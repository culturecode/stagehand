ActiveRecord::Base.class_eval do
  # SYNC CALLBACKS
  ([self] + ActiveSupport::DescendantsTracker.descendants(self)).each do |klass|
    klass.define_model_callbacks :sync, :sync_as_subject, :sync_as_affected
  end

  # SYNC STATUS
  def self.inherited(subclass)
    super

    subclass.class_eval do
      has_one :stagehand_unsynced_indicator,
        lambda { where(:stagehand_commit_entries => {:table_name => subclass.table_name}).readonly },
        :class_name => 'Stagehand::Staging::CommitEntry',
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

  # MULTITHREADED CONNECTION HANDLING

  # The original implementation of remove_connection uses @connection_specification_name, which is shared across Threads.
  # We have overridden writes to that variable so they are stored in Thread.current, but we need to swap it in when a
  # connection is removed.
  def self.remove_connection(name = nil)
    old = @connection_specification_name
    @connection_specification_name = connection_specification_name
    super
  ensure
    @connection_specification_name = old
  end

  def self.connection_specification_name=(connection_name)
    load_stagehand_connection_specification_name
    Thread.current['Stagehand:connection_specification_name'][self.name] = connection_name
  end

  def self.connection_specification_name
    load_stagehand_connection_specification_name
    Thread.current['Stagehand:connection_specification_name'][self.name] || super
  end

  def self.load_stagehand_connection_specification_name
    Thread.current['Stagehand:connection_specification_name'] ||= {}
  end
end
