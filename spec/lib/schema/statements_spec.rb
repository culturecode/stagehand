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

  describe '#drop_table' do
    without_transactional_fixtures

    before do
      ActiveRecord::Schema.define { create_table('widgets') }
    end

    let(:entry) { Stagehand::Staging::CommitEntry.where(:table_name => 'widgets').save_operations.create }

    it 'automatically removes entries with the given table name' do
      expect { ActiveRecord::Schema.define { drop_table('widgets') } }
        .to change { entry.class.exists?(entry.id) }
        .to(false)
    end

    it 'deletes empty commits' do
      commit = Stagehand::Staging::Commit.capture { }
      expect { ActiveRecord::Schema.define { drop_table('widgets') } }
        .to change { Stagehand::Staging::Commit.all.include?(commit) }
        .to(false)
    end
  end
end
