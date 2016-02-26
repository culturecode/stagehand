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

  describe '#will_create' do
    let(:other_record) { SourceRecord.create }

    it 'returns affected_records from the staging database that do not exist in the production database' do
      Stagehand::Staging::Commit.capture { source_record.touch; other_record.touch }
      expect(subject.will_create).to include(other_record)
    end

    it 'does not return affected_records from the staging database that exist in the production database' do
      Stagehand::Production.save(other_record)
      Stagehand::Staging::Commit.capture { source_record.touch; other_record.touch }
      expect(subject.will_create).not_to include(other_record)
    end

    it 'does not return records from delete operation entries' do
      Stagehand::Production.save(other_record)
      Stagehand::Staging::Commit.capture { source_record.delete }
      expect(subject.will_create).not_to include(source_record)
    end
  end

  describe '#will_delete' do
    it 'returns affected_records from the production database that do not exist in the staging database' do
      Stagehand::Production.save(source_record)
      Stagehand::Staging::Commit.capture { source_record.delete }

      expect(subject.will_delete).to include(source_record)
    end
  end

  describe '#can_update' do
    it 'returns affected_records from the production database that have been updated in the staging database' do
      Stagehand::Production.save(source_record)
      Stagehand::Staging::Commit.capture { source_record.update_attributes(:updated_at => 10.days.from_now) }

      expect(subject.can_update).to include(source_record)
    end

    it 'does not return records that do not differ between the staging database and production database' do
      Stagehand::Staging::Commit.capture { source_record.touch }
      Stagehand::Production.save(source_record)

      expect(subject.can_update).not_to include(source_record)
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
