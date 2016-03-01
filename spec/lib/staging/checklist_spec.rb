require 'rails_helper'

describe Stagehand::Staging::Checklist do
  subject { Stagehand::Staging::Checklist.new(source_record) }
  let(:source_record) { SourceRecord.create }

  describe '#affected_records' do
    it 'returns the given record even if it has no related commits' do
      expect(subject.affected_records).to include(source_record)
    end

    it "returns all records from commits that overlap the given record" do
      other_record = SourceRecord.create
      other_other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { source_record.touch }
      Stagehand::Staging::Commit.capture { source_record.touch; other_record.touch }
      Stagehand::Staging::Commit.capture { other_record.touch; other_other_record.touch }

      expect(subject.affected_records).to include(source_record, other_record)
    end

    it "returns all records from commits that overlap each other, at least of which contains the given record" do
      other_record = SourceRecord.create
      other_other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { source_record.touch }
      Stagehand::Staging::Commit.capture { source_record.touch; other_record.touch }
      Stagehand::Staging::Commit.capture { other_record.touch; other_other_record.touch }

      expect(subject.affected_records).to include(other_other_record)
    end

    it "does not return records from commits that are disjoint from any commit that overlaps, or indirectly overlaps the given record" do
      other_record = SourceRecord.create
      other_other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { source_record.touch }
      Stagehand::Staging::Commit.capture { other_other_record.touch }

      expect(subject.affected_records).not_to include(other_other_record)
    end

    it 'does not return duplicate records' do
      other_record = SourceRecord.create
      other_other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { source_record.touch }
      Stagehand::Staging::Commit.capture { source_record.touch; other_record.touch }

      records = subject.affected_records.to_a
      expect { records.uniq! }.not_to change { records.length }
    end
  end

  describe '#confirm_create' do
    let(:other_record) { SourceRecord.create }

    it 'returns affected_records that have create operation entries that are part of a commit' do
      Stagehand::Staging::Commit.capture { source_record }
      expect(subject.confirm_create).to include(source_record)
    end

    it 'returns affected_records that have create and update operation entries that are part of a commit' do
      Stagehand::Staging::Commit.capture { source_record.touch }
      expect(subject.confirm_create).to include(source_record)
    end

    it 'does not return affected_records that have delete, create and update operation entries that are part of a commit' do
      Stagehand::Staging::Commit.capture { source_record.touch; source_record.destroy }
      expect(subject.confirm_create).not_to include(source_record)
    end

    it 'does not return affected_records that have create operation entries that are part of a commit, and delete entries not part of a commit' do
      Stagehand::Staging::Commit.capture { source_record }
      source_record.destroy
      expect(subject.confirm_create).not_to include(source_record)
    end

    it 'does not return affected_records that have create operation entries that are not part of a commit' do
      expect(subject.confirm_create).not_to include(source_record)
    end
  end

  describe '#confirm_delete' do
    before { Stagehand::Production.save(source_record) }

    it 'returns affected_records that have delete operation entries that are part of a commit' do
      Stagehand::Staging::Commit.capture { source_record.destroy }
      expect(subject.confirm_delete).to include(source_record)
    end

    it 'returns affected_records that have delete, create and update operation entries' do
      Stagehand::Staging::Commit.capture { source_record.touch; source_record.destroy }
      expect(subject.confirm_delete).to include(source_record)
    end

    it 'does not include nil entries if delete operation entries include records that do not exist on production' do
      Stagehand::Production.destroy(source_record)
      Stagehand::Staging::Commit.capture { source_record.destroy }
      expect(subject.confirm_delete).not_to include(source_record)
    end
  end

  describe '#confirm_update' do
    it 'returns affected_records that have update operation entries that are part of a commit' do
      source_record
      Stagehand::Staging::Commit.capture { source_record.touch }
      expect(subject.confirm_update).to include(source_record)
    end

    it 'does not return affected_records that have update and create operation entries' do
      Stagehand::Staging::Commit.capture { source_record.touch }
      expect(subject.confirm_update).not_to include(source_record)
    end

    it 'does not return affected_records that have update and delete operation entries' do
      source_record
      Stagehand::Staging::Commit.capture { source_record.touch; source_record.destroy }
      expect(subject.confirm_update).not_to include(source_record)
    end
  end

  describe '#requires_confirmation' do
    it 'returns affected_records that appear in commits where the staging_record is not in the start_operation' do
      Stagehand::Staging::Commit.capture { source_record.touch }
      expect(subject.requires_confirmation).to include(source_record)
    end

    it 'does not return affected_records that only appear in commits where the staging_record is in the start_operation' do
      Stagehand::Staging::Commit.capture(source_record) { source_record.touch }
      expect(subject.requires_confirmation).not_to include(source_record)
    end

    it 'returns affected_records that appear in commits where the staging_record is not in the start_operation and other where it is' do
      Stagehand::Staging::Commit.capture(source_record) { source_record.touch }
      Stagehand::Staging::Commit.capture { source_record.touch }

      expect(subject.requires_confirmation).to include(source_record)
    end

    it 'does not return affected_records that only appear in outside of commits' do
      source_record
      expect(subject.requires_confirmation).not_to include(source_record)
    end

    it 'does not return duplicate records' do
      Stagehand::Staging::Commit.capture { source_record.touch }
      Stagehand::Staging::Commit.capture { source_record.touch }
      records = subject.requires_confirmation

      expect { records.uniq! }.not_to change { records.count }
    end

    it 'returns records that pass the condition in the block provided to the constructor' do
      other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { other_record.touch; source_record.touch }
      subject = Stagehand::Staging::Checklist.new(source_record) do |record|
        record.id == source_record.id
      end

      expect(subject.requires_confirmation).to include(source_record)
    end

    it 'does not return records that do not pass the condition in the block provided to the constructor' do
      other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { other_record.touch; source_record.touch }
      subject = Stagehand::Staging::Checklist.new(source_record) do |record|
        record.id != source_record.id
      end

      expect(subject.requires_confirmation).not_to include(source_record)
    end

    it 'does not include records that only appear in the start_operation' do
      Stagehand::Staging::Commit.capture(source_record) { SourceRecord.create }
      expect(subject.requires_confirmation).not_to include(source_record)
    end
  end

  # # self => hm:t => unpublished
  # it 'publishes an unpublished record related with a hm:t association'
  #
  # # self => [changed, unchanged, changed]
  # it 'republishes hm association records whose attributes have changed'
  #
  # # self => [join, deleted, join] => [record, record]
  # it 'deletes associated hm:t join records if they no longer exist in staging'
end
