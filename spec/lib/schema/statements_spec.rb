require 'rails_helper'

describe Stagehand::Schema::Statements do
  describe '#rename_table' do
    without_transactional_fixtures

    after do
      ActiveRecord::Schema.define { drop_table('doodads') }
    end

    let(:entry) { Stagehand::Staging::CommitEntry.where(:table_name => 'widgets').save_operations.create }

    it 'updates the table name column of commit entries for the given table' do
      create_table('widgets', :stagehand => true)
      expect { ActiveRecord::Schema.define { rename_table('widgets', 'doodads') } }
        .to change { entry.reload.table_name }
        .to('doodads')
    end

    it 'does not run if the table does not have stagehand' do
      create_table('widgets', :stagehand => false)
      expect { ActiveRecord::Schema.define { rename_table('widgets', 'doodads') } }
        .not_to change { entry.reload.table_name }
    end

    def create_table(*args, **options)
      ActiveRecord::Schema.define { create_table(*args, :force => true, **options) }
    end
  end
end
