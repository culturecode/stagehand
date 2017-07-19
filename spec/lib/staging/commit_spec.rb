require 'rails_helper'

describe Stagehand::Staging::Commit do
  let(:klass) { Stagehand::Staging::Commit }
  let(:source_record) { SourceRecord.create }

  describe ':all' do
    it 'returns all commits' do
      commit_1 = klass.capture { }
      commit_2 = klass.capture { }
      expect(klass.all).to contain_exactly(commit_1, commit_2)
    end

    it 'does not return incomplete commits' do
      commit_1 = klass.capture { }
      commit_2 = klass.capture { }
      commit_3 = klass.capture { }
      commit_2.entries.end_operations.delete_all
      commit_3.entries.start_operations.delete_all

      expect(klass.all).to contain_exactly(commit_1)
    end
  end

  describe '::capturing?' do
    it 'is false while not capturing' do
      expect(klass).not_to be_capturing
    end

    it 'is true while capturing' do
      klass.capture do
        expect(klass).to be_capturing
      end
    end
  end

  describe '::capture' do
    it 'commits records that were created' do
      commit = klass.capture { source_record }
      expect(commit).to include(source_record)
    end

    it 'does not include records modified outside of the block' do
      source_record
      commit = klass.capture {  }
      expect(commit).not_to include(source_record)
    end

    it 'does not affect the commit_id of entries for records modified outside of the block' do
      source_record
      entry = Stagehand::Staging::CommitEntry.last
      expect { klass.capture {  } }.not_to change { entry.reload.attributes }
    end

    it 'commits records that were updated' do
      source_record
      commit = klass.capture { source_record.increment!(:counter) }
      expect(commit).to include(source_record)
    end

    it 'commits records that were destroyed' do
      source_record
      commit = klass.capture { source_record.destroy }
      expect(commit).to include(source_record)
    end

    it 'commits records that were deleted' do
      source_record
      commit = klass.capture { source_record.delete }
      expect(commit).to include(source_record)
    end

    it 'accepts a "subject" record to indicate which record kicked off the changes in the commit' do
      commit = klass.capture(source_record) { }
      expect(commit.subject).to eq(source_record)
    end

    it 'does not record the subject if it does not have an id' do
      source_record.id = nil
      commit = klass.capture(source_record) { }
      expect(commit.subject).to be_nil
    end

    it 'includes the subject record' do
      commit = klass.capture(source_record) { }
      expect(commit).to include(source_record)
    end

    it 'does not include the subject record if it does not have an id' do
      source_record.id = nil
      commit = klass.capture(source_record) { }
      expect(commit).not_to include(source_record)
    end

    it 'allows the subject to be set during the block' do
      commit = klass.capture do |commit|
        commit.subject = source_record
      end
      expect(commit.subject).to eq(source_record)
    end

    it 'does not set the subject if during the block if the subject does not have an id' do
      commit = klass.capture do |commit|
        source_record.id = nil
        commit.subject = source_record
      end
      expect(commit.subject).to be_nil
    end

    it 'does not swallow exceptions from the given block' do
      expect { klass.capture { raise('test') } }.to raise_exception('test')
    end

    it 'ends the commit when the block raises an exception' do
      expect { klass.capture { raise } rescue nil }
        .to change { Stagehand::Staging::CommitEntry.end_operations.count }.by(1)
    end

    it 'does not create duplicate end entries if an exception is raised while ending the commit' do
      allow(klass).to receive(:new).and_raise('an error')
      expect { klass.capture { } rescue nil }
        .to change { Stagehand::Staging::CommitEntry.end_operations.count }.by(1)
    end

    it 'does not contain entries from tables in the :except option' do
      commit = klass.capture(:except => :source_records) { source_record }
      expect(commit).not_to include(source_record)
    end

    it 'contains entries from tables in the :except option if the table is the same as the subject' do
      commit = klass.capture(source_record, :except => :source_records) { source_record.increment!(:counter) }
      expect(commit).to include(source_record)
    end

    context 'if the session trigger has not been created' do
      before(:context) { Stagehand::Schema.send :drop_trigger, :stagehand_commit_entries, :insert }
      after(:context) { Stagehand::Schema.send :create_session_trigger }

      it 'raises an exception if the commit session is not set' do
        expect { klass.capture { } }.to raise_exception(Stagehand::BlankCommitEntrySession)
      end
    end

    it 'sets the start timestamp' do
      expect(klass.capture { }.entries.first).to have_attributes(:created_at => be_present)
    end

    it 'sets the end timestamp' do
      expect(klass.capture { }.entries.last).to have_attributes(:created_at => be_present)
    end
  end

  describe '::find' do
    it 'returns the commit with the same the given id' do
      commit_1 = klass.capture { }
      commit_2 = klass.capture { }
      expect(klass.find(commit_2.id)).to eq(commit_2)
    end

    it 'accepts multiple ids and returns an array' do
      commit_1 = klass.capture { }
      commit_2 = klass.capture { }
      expect(klass.find([commit_1.id, commit_2.id])).to contain_exactly(commit_1, commit_2)
    end

    it 'ignores a nil commit id' do
      expect(klass.find(nil)).to be_nil
    end

    it 'ignores nil commit ids in arrays' do
      commit_1 = klass.capture { }
      expect(klass.find([commit_1.id, nil])).to contain_exactly(commit_1)
    end
  end

  describe '::containing' do
    let!(:commit) { klass.capture { source_record } }
    let!(:other_commit) { klass.capture { SourceRecord.create } }

    it 'returns commits that contain the given commit_entry' do
      expect(klass.containing(source_record)).to include(commit)
    end

    it 'returns commits that contain the given commit_entry when there is a matching entry with no commit' do
      source_record.increment!(:counter)
      expect(klass.containing(source_record)).to include(commit)
    end

    it 'does not return commits that do not contain the given commit_entry' do
      expect(klass.containing(source_record)).not_to include(other_commit)
    end
  end

  describe '#commit_id' do
    subject { klass.capture {} }

    it 'matches the id of the start operation' do
      subject
      start_operation = Stagehand::Staging::CommitEntry.start_operations.last
      expect(subject).to have_attributes(:id => start_operation.id)
    end

    it 'is not affected by the order the database returns commit entries' do
      Stagehand::Staging::CommitEntry.order(:id => :asc).scoping do
        subject
      end

      Stagehand::Staging::CommitEntry.order(:id => :desc).scoping do
        expect(klass.new(subject.id)).to have_attributes(:id => subject.id)
      end
    end
  end

  describe '#entries' do
    it 'returns insert operations' do
      commit = klass.capture { source_record }
      expect(commit.entries).to include( be_insert_operation )
    end

    it 'returns update operations' do
      commit = klass.capture { source_record.increment!(:counter) }
      expect(commit.entries).to include( be_update_operation )
    end

    it 'returns delete operations' do
      commit = klass.capture { source_record.delete }
      expect(commit.entries).to include( be_delete_operation )
    end

    it 'returns start operations' do
      commit = klass.capture { source_record.increment!(:counter) }
      expect(commit.entries).to include( be_start_operation )
    end

    it 'returns end operations' do
      commit = klass.capture { source_record.increment!(:counter) }
      expect(commit.entries).to include( be_end_operation )
    end
  end

  describe '#subject' do
    it 'returns the record of the start entry' do
      expect(klass.capture(source_record) { }.subject).to eq(source_record)
    end
  end

  describe '#empty?' do
    subject { klass.capture { source_record } }

    it 'is empty if the commit has no content operatings' do
      subject.entries.content_operations.delete_all
      expect(subject).to be_empty
    end

    it 'is not empty if the commit has content operations' do
      expect(subject).not_to be_empty
    end
  end

  describe 'equality' do
    subject { klass.capture { } }
    let(:other) { klass.capture { } }

    it 'is not equal to another commit' do
      expect(subject).not_to eq(other)
    end

    it 'is equal to another commit if the ids match' do
      allow(other).to receive(:id).and_return(subject.id)
      expect(subject).to eq(other)
    end

    it 'remove duplicates from an array using uniq' do
      allow(other).to receive(:id).and_return(subject.id)
      expect([subject, other].uniq).to contain_exactly(subject)
    end
  end

  describe 'database transaction' do
    let(:source_record) { SourceRecord.create }

    it 'records entries correctly if the transaction is contained in the capture block' do
      commit = klass.capture do
        ActiveRecord::Base.transaction do
          source_record.increment!(:counter)
        end
      end

      expect(commit).to include(source_record)
    end

    it 'rollback removes entries if the transaction is contained in the capture block' do
      commit = klass.capture do
        ActiveRecord::Base.transaction do
          source_record.increment!(:counter)
          raise ActiveRecord::Rollback
        end
      end

      expect(commit).not_to include(source_record)
    end
  end
end
