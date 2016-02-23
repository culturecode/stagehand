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
  end

  describe '::find' do
    it 'returns the commit with the same the given id' do
      commit_1 = klass.capture { }
      commit_2 = klass.capture { source_record }

      expect(klass.find(commit_2.id)).to eq(commit_2)
    end
  end

  describe '::with_identifier' do
    it 'loads existing commit entries matching the identifier' do
      commit_1 = klass.capture('test') { source_record }
      expect(klass.with_identifier('test')).to contain_exactly(commit_1)
    end

    it 'returns an empty array if no commit entries matched the given identifier' do
      expect(klass.with_identifier('test')).to be_empty
    end

    it 'accepts multiple identifiers to find' do
      commit_1 = klass.capture('test') { source_record }
      commit_2 = klass.capture('test2') { source_record }
      expect(klass.with_identifier('test', 'test2')).to contain_exactly(commit_1, commit_2)
    end

    it 'accepts an array of identifiers to find' do
      commit_1 = klass.capture('test') { source_record }
      commit_2 = klass.capture('test2') { source_record }
      expect(klass.with_identifier(['test', 'test2'])).to contain_exactly(commit_1, commit_2)
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
end
