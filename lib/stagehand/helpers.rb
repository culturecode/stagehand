module Stagehand
  def self.extract_key(staging_record, table_name = nil)
    case staging_record
    when Staging::CommitEntry
      id = staging_record.record_id
      table_name = staging_record.table_name
    when ActiveRecord::Base
      id = staging_record.id
      table_name = staging_record.class.table_name
    else
      id = staging_record
    end

    raise 'Invalid input' unless table_name && id

    return [table_name, id]
  end
end
