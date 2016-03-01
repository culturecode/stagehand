require 'rails_helper'

describe Stagehand::Staging::CommitEntry do
  let(:klass) { Stagehand::Staging::CommitEntry }
  let(:source_record) { SourceRecord.create }
  subject { source_record; Stagehand::Staging::CommitEntry.last }

  describe '::matching' do
    it 'returns a list of entries that match the given source_record' do
      expect(Stagehand::Staging::CommitEntry.matching(source_record)).to contain_exactly(subject)
    end

    it 'returns a list of entries that match the given CommitEntry' do
      other_entry = subject.dup
      other_entry.save
      expect(Stagehand::Staging::CommitEntry.matching(subject)).to contain_exactly(subject, other_entry)
    end

    it 'returns a list of entries that match the given array of source records' do
      expect(Stagehand::Staging::CommitEntry.matching([source_record])).to contain_exactly(subject)
    end

    it 'returns an empty array if given an empty array' do
      source_record
      expect(Stagehand::Staging::CommitEntry.matching([])).to be_empty
    end

    it 'returns an empty array if given a nil' do
      source_record
      expect(Stagehand::Staging::CommitEntry.matching(nil)).to be_empty
    end
  end

  describe '#record' do
    context 'on an insert operation entry' do
      it 'returns the record represented by the row that triggered this entry' do
        expect(subject.record).to eq(source_record)
      end
    end

    context 'on a delete operation entry' do
      before do
        Stagehand::Production.save(source_record)
        source_record.reload # reload ensures timestamps are only as accurate as the database can store
        source_record.delete
      end

      it 'returns an object whose attributes are populated by the production record for delete operation entries' do
        expect(subject.record).to have_attributes(source_record.attributes)
      end

      it 'returns the production record for delete operation entries' do
        expect(subject.record).to be_a(source_record.class)
      end

      it 'raises a read_only exception when saving' do
        expect { subject.record.save }.to raise_exception(ActiveRecord::ReadOnlyRecord)
      end

      it 'raises an exception if the record class could not be determined from the table_name' do
        entry = klass.create(:record_id => 1, :table_name => 'fake_table', :operation => :insert)
        expect { entry.record }.to raise_exception(Stagehand::IndeterminateRecordClass)
      end
    end
  end
end
