require 'rails_helper'

describe Stagehand::Staging::Commit do
  let(:source_record) { SourceRecord.create }

  describe '::new' do
    it 'commits records that were created' do
      commit = Stagehand::Staging::Commit.new { source_record }
      expect(commit).to include(source_record)
    end

    it 'does not include records modified outside of the block' do
      source_record
      commit = Stagehand::Staging::Commit.new {  }
      expect(commit).not_to include(source_record)
    end

    it 'commits records that were updated' do
      source_record
      commit = Stagehand::Staging::Commit.new { source_record.touch }
      expect(commit).to include(source_record)
    end

    it 'commits records that were destroyed' do
      source_record
      commit = Stagehand::Staging::Commit.new { source_record.destroy }
      expect(commit).to include(source_record)
    end

    it 'commits records that were deleted' do
      source_record
      commit = Stagehand::Staging::Commit.new { source_record.delete }
      expect(commit).to include(source_record)
    end

    it 'includes all entries from commits with matching identifiers' do
      commit_1 = Stagehand::Staging::Commit.new('test') { }
      commit_2 = Stagehand::Staging::Commit.new('test') { source_record }

      expect(Stagehand::Staging::Commit.new('test').entries).to include(*commit_2.entries)
    end
  end

  describe '::with_identifier' do
    it 'loads existing commit entries matching the idenfitier if no block is given' do
      commit_1 = Stagehand::Staging::Commit.new('test') { source_record }
      expect(Stagehand::Staging::Commit.with_identifier('test')).to contain_exactly(commit_1)
    end

    it 'returns nil if no block is given and no commit entries matched the given identifier' do
      expect(Stagehand::Staging::Commit.with_identifier('test')).to be_empty
    end

    it 'accepts multiple identifiers to find' do
      commit_1 = Stagehand::Staging::Commit.new('test') { source_record }
      commit_2 = Stagehand::Staging::Commit.new('test2') { source_record }
      expect(Stagehand::Staging::Commit.with_identifier('test', 'test2')).to contain_exactly(commit_1, commit_2)
    end

    it 'accepts an array of identifiers to find' do
      commit_1 = Stagehand::Staging::Commit.new('test') { source_record }
      commit_2 = Stagehand::Staging::Commit.new('test2') { source_record }
      expect(Stagehand::Staging::Commit.with_identifier(['test', 'test2'])).to contain_exactly(commit_1, commit_2)
    end
  end

  describe '::containing' do
    let!(:commit) { Stagehand::Staging::Commit.new { source_record } }
    let!(:other_commit) { Stagehand::Staging::Commit.new { SourceRecord.create } }

    it 'returns commits that contain the given commit_entry' do
      expect(Stagehand::Staging::Commit.containing(source_record)).to include(commit)
    end

    it 'returns commits that contain the given commit_entry when there is a matching entry with no commit' do
      source_record.touch
      expect(Stagehand::Staging::Commit.containing(source_record)).to include(commit)
    end

    it 'does not return commits that do not contain the given commit_entry' do
      expect(Stagehand::Staging::Commit.containing(source_record)).not_to include(other_commit)
    end
  end

  describe '#entries' do
    it 'returns insert operations' do
      commit = Stagehand::Staging::Commit.new { source_record }
      expect(commit.entries).to include( be_insert_operation )
    end

    it 'returns update operations' do
      commit = Stagehand::Staging::Commit.new { source_record.touch }
      expect(commit.entries).to include( be_update_operation )
    end

    it 'returns delete operations' do
      commit = Stagehand::Staging::Commit.new { source_record.delete }
      expect(commit.entries).to include( be_delete_operation )
    end

    it 'does not return start or end operations' do
      commit = Stagehand::Staging::Commit.new { source_record.touch }
      expect(commit.entries).not_to include( be_start_operation.or be_end_operation )
    end
  end

  describe '#related_commits' do
    subject { Stagehand::Staging::Commit.new { source_record.touch } }

    it 'returns a list of commits that contain entries for any of the records present in this commit' do
      other_commit = Stagehand::Staging::Commit.new { source_record.touch }
      expect(subject.related_commits).to include(other_commit)
    end

    it 'does not include commits that do not contain entries for any of the records present in this commit' do
      other_commit = Stagehand::Staging::Commit.new { SourceRecord.create }
      expect(subject.related_commits).not_to include(other_commit)
    end
  end
end
