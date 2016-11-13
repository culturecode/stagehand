require 'stagehand/auditor/checklist_visualizer'

module Stagehand
  module Auditor
    extend self

    def incomplete_commits
      incomplete = []

      incomplete_start_operations.each do |start_operation|
        entries = records_until_match(start_operation, :asc, :operation => Staging::CommitEntry::START_OPERATION).to_a
        incomplete << [start_operation.id, entries]
      end

      incomplete_end_operations.each do |end_operation|
        entries = records_through_match(end_operation, :desc, :operation => Staging::CommitEntry::START_OPERATION).to_a
        incomplete << [entries.last.id, entries]
      end

      return incomplete.to_h
    end

    def mismatched_records
      output = {}

      tables = Database.staging_connection.tables.select {|table_name| Schema::has_stagehand?(table_name) }
      tables.each do |table_name|
        print "\nChecking #{table_name} "
        mismatched = {}
        limit = 1000
        index = 0

        loop do
          production_records = Database.production_connection.select_all("SELECT * FROM #{table_name} LIMIT #{limit} OFFSET #{limit * index}")
          staging_records = Database.staging_connection.select_all("SELECT * FROM #{table_name} LIMIT #{limit} OFFSET #{limit * index}")
          id_column = production_records.columns.index('id')

          production_differences = production_records.rows - staging_records.rows
          staging_differences = staging_records.rows - production_records.rows

          production_differences.each do |row|
            id = row[id_column]
            mismatched[id] = {:production => row}
          end
          staging_differences.each do |row|
            id = row[id_column]
            mismatched[id] ||= {:staging => row}
          end

          if production_differences.present? || staging_differences.present?
            print '!'
          else
            print '.'
          end

          index += 1
          break unless staging_records.present? || production_records.present?
        end

        if mismatched.present?
          print " #{mismatched.count} mismatched"
          output[table_name] = mismatched
        end
      end

      return output
    end

    def visualize(subject, output_file_name)
      visualize_checklist(Staging::Checklist.new(subject), output_file_name)
    end

    def visualize_checklist(checklist, output_file_name)
      ChecklistVisualizer.new(checklist).output(output_file_name)
    end

    private

    # Incomplete End Operation that are not the last entry in their session
    def incomplete_end_operations
      last_entry_per_session = Staging::CommitEntry.group(:session).select('MAX(id) AS id')
      return Staging::CommitEntry.uncontained.end_operations.where.not(:id => last_entry_per_session)
    end

    # Incomplete Start on the same session as a subsequent start operation
    def incomplete_start_operations
      last_start_entry_per_session = Staging::CommitEntry.start_operations.group(:session).select('MAX(id) AS id')
      return Staging::CommitEntry.uncontained.start_operations.where.not(:id => last_start_entry_per_session)
    end

    def records_until_match(start_entry, direction, match_attributes)
      records_through_match(start_entry, direction, match_attributes)[0..-2]
    end

    def records_through_match(start_entry, direction, match_attributes)
      last_entry = next_match(start_entry, direction, match_attributes)
      return records_from(start_entry, direction).where.not("id #{exclusive_comparator(direction)} ?", last_entry)
    end

    def next_match(start_entry, direction, match_attributes)
      records_from(start_entry, direction).where.not(:id => start_entry.id).where(match_attributes).first
    end

    def records_from(start_entry, direction)
      scope = Staging::CommitEntry.where(:session => start_entry.session).where("id #{comparator(direction)} ?", start_entry.id)
      scope = scope.reverse_order if direction == :desc
      return scope
    end

    def comparator(direction)
      exclusive_comparator(direction) + '='
    end

    def exclusive_comparator(direction)
      direction == :asc ? '>' : '<'
    end
  end
end
