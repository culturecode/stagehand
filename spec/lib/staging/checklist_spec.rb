require 'rails_helper'

describe Stagehand::Staging::Checklist do
  let(:klass) { Stagehand::Staging::Checklist }
  let(:source_record) { SourceRecord.create }
  let(:other_record) { SourceRecord.create }

  subject { Stagehand::Staging::Checklist.new(source_record, preconfirm_subject: false) }

  describe '::new' do
    it 'raises an exception if no subject record is provided'
  end

  describe '::related_entries' do
    let(:commit) { Stagehand::Staging::Commit.capture { source_record.increment!(:counter) } }

    it "accepts a single entry" do
      source_record.increment!(:counter)
      commit_entry = Stagehand::Staging::CommitEntry.last
      checklist = klass.new(commit_entry)

      expect(checklist.affected_records).to include(source_record)
    end

    it "accepts multiple entries" do
      source_record.increment!(:counter)
      commit_entry = Stagehand::Staging::CommitEntry.last
      other_record
      other_commit_entry = Stagehand::Staging::CommitEntry.last
      checklist = klass.new([commit_entry, other_commit_entry])

      expect(checklist.affected_records).to include(source_record)
    end

    it "accepts a record" do
      checklist = klass.new(source_record)
      expect(checklist.affected_records).to include(source_record)
    end

    it "accepts multiple records" do
      checklist = klass.new([source_record, other_record])
      expect(checklist.affected_records).to include(source_record, other_record)
    end


    it 'returns all entries from commits that contain entries matching the given entries' do
      source_record.increment!(:counter)
      commit_entry = Stagehand::Staging::CommitEntry.last
      commit = Stagehand::Staging::Commit.capture { source_record.increment!(:counter); SourceRecord.create }

      expect(klass.related_entries(commit_entry)).to include(*commit.entries)
    end

    it 'does not return entries unrelated to commits the given entry is a part of' do
      other_commit = Stagehand::Staging::Commit.capture { SourceRecord.create }
      expect(klass.related_entries(commit.entries)).not_to include(*other_commit.entries)
    end

    it 'returns related entries that are not part of a commit' do
      source_record.increment!(:counter)
      commit_entry = Stagehand::Staging::CommitEntry.last
      expect(klass.related_entries(commit.entries)).to include(commit_entry)
    end

    it "does not include unrelated uncontained entries when it includes related uncontained entries" do
      unrelated_entry = SourceRecord.create; Stagehand::Staging::CommitEntry.last
      source_record.increment!(:counter)
      expect(klass.related_entries(commit.entries)).not_to include(unrelated_entry)
    end

    # 1{ 2 }  3{ 1, 3 } --- Includes 3{ 1, 3 }
    it "returns all operations for a commit directly related only through content operations" do
      record_1 = SourceRecord.create
      record_2 = SourceRecord.create
      record_3 = SourceRecord.create

      commit_1 = Stagehand::Staging::Commit.capture(record_1) { record_2.increment!(:counter) }
      commit_3 = Stagehand::Staging::Commit.capture(record_3) { record_1.increment!(:counter); record_3.increment!(:counter) }

      expect(klass.related_entries(record_1)).to include(*commit_3.entries)
    end

    # 1{ 2 }  3{ 2 }  4{ 3, 4 } --- Doesn't include 4{ 3, 4 }
    it "does not return any operations indirectly related only through control operations" do
      record_1 = SourceRecord.create
      record_2 = SourceRecord.create
      record_3 = SourceRecord.create
      record_4 = SourceRecord.create

      commit_1 = Stagehand::Staging::Commit.capture(record_1) { record_2.increment!(:counter) }
      commit_3 = Stagehand::Staging::Commit.capture(record_3) { record_2.increment!(:counter) }
      commit_4 = Stagehand::Staging::Commit.capture(record_4) { record_3.increment!(:counter); record_4.increment!(:counter) }

      expect(klass.related_entries(record_1)).not_to include(*commit_4.entries)
    end

    # 1{ 2 }  3{ 2 } --- Includes 3{ 2 }
    it "returns all operations indirectly related only through content operations" do
      record_1 = SourceRecord.create
      record_2 = SourceRecord.create
      record_3 = SourceRecord.create

      commit_1 = Stagehand::Staging::Commit.capture(record_1) { record_2.increment!(:counter) }
      commit_3 = Stagehand::Staging::Commit.capture(record_3) { record_2.increment!(:counter) }

      expect(klass.related_entries(record_1)).to include(*commit_3.entries)
    end


    it 'does not return duplicates if when passed an uncontained entry for a record that also appears in a commit' do
      source_record.increment!(:counter)
      commit_entry = Stagehand::Staging::CommitEntry.last
      entries = klass.related_entries(commit_entry)

      expect(entries.length).to eq(entries.uniq.length)
    end
  end

  describe '::associated_records' do
    let(:record_1) { SourceRecord.create }
    let(:record_2) { SourceRecord.create }
    let(:record_3) { SourceRecord.create }

    context "when another record was created outside outside of a commit" do
      before { record_2 }

      it 'includes the record if assigned during the commit via to a Has Many Through' do
        commit = Stagehand::Staging::Commit.capture { record_1.targets << record_2 }
        expect(klass.associated_records(commit.entries)).to include(record_2)
      end

      it 'includes the record if assigned during the commit via to a Has Many' do
        commit = Stagehand::Staging::Commit.capture { record_2.target_assignments.create }
        expect(klass.associated_records(commit.entries)).to include(record_2)
      end

      it 'includes the record if assigned during the commit via to a Belongs To' do
        commit = Stagehand::Staging::Commit.capture { TargetAssignment.create(:target => record_2) }
        expect(klass.associated_records(commit.entries)).to include(record_2)
      end

      it 'includes the record if assigned during the commit via to a polymorphic association' do
        commit = Stagehand::Staging::Commit.capture { record_1.update_attributes!(:attachable => record_2) }
        expect(klass.associated_records(commit.entries)).to include(record_2)
      end
    end

    it 'does not return nil entries if passed an entry without a record' do
      commit = Stagehand::Staging::Commit.capture {}
      expect(klass.associated_records(commit.entries)).not_to include(nil)
    end

    it 'does not return duplicate records if entries for the same record are passed' do
      commit = Stagehand::Staging::Commit.capture { record_1.targets << record_2; record_1.target_assignments.last.touch }
      associated_records = klass.associated_records(commit.entries)
      expect(associated_records.uniq).to eq(associated_records)
    end

    it 'does not return duplicate records if separate records are assocatied with the same record' do
      commit = Stagehand::Staging::Commit.capture { record_1.targets << record_2; record_3.targets << record_2 }
      associated_records = klass.associated_records(commit.entries)
      expect(associated_records.uniq).to eq(associated_records)
    end

    it 'does not include entries for tables that do not exist in production' do
      user = User.new
      commit = Stagehand::Staging::Commit.capture { record_1.update_attributes!(:user => user) }
      expect(klass.associated_records(commit.entries)).not_to include(user)
    end
  end

  describe '#affected_records' do
    it 'returns the given record with commit entries even if it has no related commits' do
      expect(subject.affected_records).to include(source_record)
    end

    it "returns all records from commits that overlap the given record" do
      other_record
      other_other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter); other_record.increment!(:counter) }
      Stagehand::Staging::Commit.capture { other_record.increment!(:counter); other_other_record.increment!(:counter) }

      expect(subject.affected_records).to include(source_record, other_record)
    end

    it "returns all records from commits that have content_operations indirectly related to the given record" do
      other_record
      other_other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter); other_record.increment!(:counter) }
      Stagehand::Staging::Commit.capture { other_record.increment!(:counter); other_other_record.increment!(:counter) }

      expect(subject.affected_records).to include(other_other_record)
    end

    it "does not return records from commits that are disjoint from any commit that overlaps, or indirectly overlaps the given record" do
      other_record
      other_other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      Stagehand::Staging::Commit.capture { other_other_record.increment!(:counter) }

      expect(subject.affected_records).not_to include(other_other_record)
    end

    it 'does not return duplicate records' do
      other_record
      other_other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter); other_record.increment!(:counter) }

      records = subject.affected_records.to_a
      expect { records.uniq! }.not_to change { records.length }
    end

    it 'returns records from associated_records' do
      other_record
      commit_1 = Stagehand::Staging::Commit.capture { source_record.targets << other_record }
      expect(subject.affected_records).to include(other_record)
    end

    it 'returns records spidered through associated_records' do
      other_record
      commit_1 = Stagehand::Staging::Commit.capture { source_record.targets << other_record }

      expect(subject.affected_records).to include(other_record)
    end
  end

  describe '#syncing_entries' do
    it 'returns uncontained deletes matching the record' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      source_record.delete
      expect(subject.syncing_entries).to include(be_delete_operation)
    end

    it 'returns uncontained deletes related to the record' do
      other_record
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter); other_record.increment!(:counter) }
      other_record.delete

      expect(subject.syncing_entries).to include(be_delete_operation)
    end

    # 1{ 2 }  3{ 2 } --- Does not include 3{}
    it "does not return control operations indirectly related through content operations" do
      record_1 = source_record
      record_2 = SourceRecord.create
      record_3 = SourceRecord.create

      commit_1 = Stagehand::Staging::Commit.capture(record_1) { record_2.increment!(:counter) }
      commit_3 = Stagehand::Staging::Commit.capture(record_3) { record_2.increment!(:counter) }

      expect(subject.syncing_entries).not_to include(*commit_3.entries.control_operations)
    end
  end

  describe '#affected_entries' do
    it 'returns all control and content entries for all commits related to this record' do
      Stagehand::Staging::Commit.capture { source_record }
      expect(subject.affected_entries).to include(be_start_operation, be_insert_operation, be_end_operation)
    end

    it 'returns uncontained entries related to the record' do
      other_record
      entry = Stagehand::Staging::CommitEntry.last
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter); other_record.increment!(:counter) }

      expect(subject.affected_entries).to include(entry)
    end

    it 'is unaffected by a transaction rollback' do
      entry = nil
      ActiveRecord::Base.transaction do
        source_record.increment!(:counter)
        entry = Stagehand::Staging::CommitEntry.last
        subject
        raise ActiveRecord::Rollback
      end

      expect(subject.affected_entries).to include(entry)
    end

    it 'does not explode if a related record has an empty Belongs To association' do
      Stagehand::Staging::Commit.capture(source_record) { TargetAssignment.create }
      expect { subject.affected_entries }.not_to raise_exception
    end

    it 'does not return entries for records that no longer exist in either database' do
      other_record
      Stagehand::Staging::Commit.capture { source_record.targets << other_record }
      other_record.destroy

      expect(subject.affected_entries).not_to include(Stagehand::Staging::CommitEntry.matching other_record)
    end
  end

  describe '#confirm_create' do
    it 'returns affected_records that have create operation entries that are part of a commit' do
      Stagehand::Staging::Commit.capture { source_record }
      expect(subject.confirm_create).to include(source_record)
    end

    it 'returns affected_records that have create and update operation entries that are part of a commit' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      expect(subject.confirm_create).to include(source_record)
    end

    it 'does not return affected_records that have delete, create and update operation entries that are part of a commit' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter); source_record.destroy }
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
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter); source_record.destroy }
      expect(subject.confirm_delete).to include(source_record)
    end

    it 'does not include nil entries if delete operation entries include records that do not exist on production' do
      Stagehand::Production.delete(source_record)
      Stagehand::Staging::Commit.capture { source_record.destroy }
      expect(subject.confirm_delete).not_to include(source_record)
    end
  end

  describe '#confirm_update' do
    it 'returns affected_records that have update operation entries that are part of a commit' do
      source_record
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      expect(subject.confirm_update).to include(source_record)
    end

    it 'does not return affected_records that have update and create operation entries' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      expect(subject.confirm_update).not_to include(source_record)
    end

    it 'does not return affected_records that have update and delete operation entries' do
      source_record
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter); source_record.destroy }
      expect(subject.confirm_update).not_to include(source_record)
    end
  end

  describe '#requires_confirmation' do
    it 'returns affected_records that appear in commits where the staging_record is not in the start_operation' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      expect(subject.requires_confirmation).to include(source_record)
    end

    it 'does not return affected_records that only appear in commits where the staging_record is in the start_operation' do
      Stagehand::Staging::Commit.capture(source_record) { source_record.increment!(:counter) }
      expect(subject.requires_confirmation).not_to include(source_record)
    end

    it 'returns affected_records that appear in commits where the staging_record is not in the start_operation and other where it is' do
      Stagehand::Staging::Commit.capture(source_record) { source_record.increment!(:counter) }
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }

      expect(subject.requires_confirmation).to include(source_record)
    end

    it 'does not return affected_records that only appear in outside of commits' do
      source_record
      expect(subject.requires_confirmation).not_to include(source_record)
    end

    it 'does not return duplicate records' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      records = subject.requires_confirmation

      expect { records.uniq! }.not_to change { records.count }
    end

    it 'returns records that pass the condition in the block provided to the constructor' do
      other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { other_record.increment!(:counter); source_record.increment!(:counter) }
      subject = Stagehand::Staging::Checklist.new(source_record, :preconfirm_subject => false) do |record|
        record.id == source_record.id
      end

      expect(subject.requires_confirmation).to include(source_record)
    end

    it 'does not return records that do not pass the condition in the block provided to the constructor' do
      other_record = SourceRecord.create
      Stagehand::Staging::Commit.capture { other_record.increment!(:counter); source_record.increment!(:counter) }
      subject = Stagehand::Staging::Checklist.new(source_record, :preconfirm_subject => false) do |record|
        record.id != source_record.id
      end

      expect(subject.requires_confirmation).not_to include(source_record)
    end

    it 'does not include records that only appear in the start_operation' do
      Stagehand::Staging::Commit.capture(source_record) { SourceRecord.create }
      expect(subject.requires_confirmation).not_to include(source_record)
    end

    it 'does not return records that were passed in as the subject of the checklist if :preconfirm_subject => true' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      subject = Stagehand::Staging::Checklist.new(source_record, :preconfirm_subject => true)
      expect(subject.requires_confirmation).not_to include(source_record)
    end

    it 'returns records that were passed in as the subject of the checklist if :preconfirm_subject => false' do
      Stagehand::Staging::Commit.capture { source_record.increment!(:counter) }
      subject = Stagehand::Staging::Checklist.new(source_record, :preconfirm_subject => false)
      expect(subject.requires_confirmation).to include(source_record)
    end
  end
end
