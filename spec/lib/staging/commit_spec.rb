require 'rails_helper'

describe Stagehand::Staging::Commit do
  let(:klass) { Stagehand::Staging::Commit }
  let(:source_record) { SourceRecord.create }

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
      commit = klass.capture { source_record.touch }
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
      expect(commit).to include(source_record)
    end

    it 'does not swallow exceptions from the given block' do
      expect{ klass.capture { raise('test') } }.to raise_exception('test')
    end

    it 'ends the commit when the block raises an exception' do
      expect{ begin klass.capture { raise }; rescue; end }
        .to change { Stagehand::Staging::CommitEntry.end_operations.count }.by(1)
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
      source_record.touch
      expect(klass.containing(source_record)).to include(commit)
    end

    it 'does not return commits that do not contain the given commit_entry' do
      expect(klass.containing(source_record)).not_to include(other_commit)
    end
  end

  describe '#entries' do
    it 'returns insert operations' do
      commit = klass.capture { source_record }
      expect(commit.entries).to include( be_insert_operation )
    end

    it 'returns update operations' do
      commit = klass.capture { source_record.touch }
      expect(commit.entries).to include( be_update_operation )
    end

    it 'returns delete operations' do
      commit = klass.capture { source_record.delete }
      expect(commit.entries).to include( be_delete_operation )
    end

    it 'returns start operations' do
      commit = klass.capture { source_record.touch }
      expect(commit.entries).to include( be_start_operation )
    end

    it 'returns end operations' do
      commit = klass.capture { source_record.touch }
      expect(commit.entries).to include( be_end_operation )
    end
  end

  describe '#related_commits' do
    subject { klass.capture { source_record.touch } }

    it 'returns a list of commits that contain entries for any of the records present in this commit' do
      other_commit = klass.capture { source_record.touch }
      expect(subject.related_commits).to include(other_commit)
    end

    it 'does not include commits that do not contain entries for any of the records present in this commit' do
      other_commit = klass.capture { SourceRecord.create }
      expect(subject.related_commits).not_to include(other_commit)
    end
  end

  describe '#related_entries' do
    subject { klass.capture { source_record.touch } }

    it "does not include its own entries" do
      expect(subject.related_entries).not_to include(*subject.content_entries)
    end

    it 'returns a entries from other commits for records present in this commit' do
      other_commit = klass.capture { source_record.touch }
      expect(subject.related_entries).to include(*other_commit.content_entries)
    end

    it 'returns a entries from other commits related to this commit, but that do not appear in this commit' do
      other_commit = klass.capture { source_record.touch; SourceRecord.create }
      expect(subject.related_entries).to include(*other_commit.content_entries)
    end

    it 'does not include entries for records not present in this commit, or any related commit' do
      other_commit = klass.capture { SourceRecord.create }
      expect(subject.related_entries).not_to include(*other_commit.content_entries)
    end

    it 'does not return entries that are not part of a commit' do
      source_record.touch
      commit_entry = Stagehand::Staging::CommitEntry.last
      expect(subject.related_entries).not_to include(commit_entry)
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
          source_record.touch
        end
      end

      expect(commit).to include(source_record)
    end

    it 'rollback removes entries if the transaction is contained in the capture block' do
      commit = klass.capture do
        ActiveRecord::Base.transaction do
          source_record.touch
          raise ActiveRecord::Rollback
        end
      end

      expect(commit).not_to include(source_record)
    end
  end
end
