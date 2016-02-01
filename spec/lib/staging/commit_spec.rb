require 'rails_helper'

describe Stagehand::Staging::Commit do
  let(:source_record) { SourceRecord.create }

  describe '#new' do
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
  end

  describe '#find' do
    it 'loads existing commit entries matching the idenfitier if no block is given' do
      commit_1 = Stagehand::Staging::Commit.new('test') { source_record }
      commit_2 = Stagehand::Staging::Commit.find('test')
      expect(commit_1).to eq(commit_2)
    end

    it 'raises an exception if no block is given and no commit entries matched the given identifier' do
      expect { Stagehand::Staging::Commit.find('test') }.to raise_exception(Stagehand::CommitNotFound)
    end
  end

  describe '#saved' do
    subject { Stagehand::Staging::Commit.new { source_record.touch } }

    it 'returns rows that were saved during the commit' do
      expect(subject.saved).to include([source_record.id, source_record.class.table_name])
    end

    it 'does not return duplicate entries if the same record was saved twice' do
      expect(subject.saved).not_to be_many
    end
  end

  describe '#destroyed' do
    subject { Stagehand::Staging::Commit.new { source_record.delete } }

    it 'returns rows that were removed during the commit' do
      expect(subject.destroyed).to include([source_record.id, source_record.class.table_name])
    end
  end
end
