describe Stagehand::Staging::CommitEntry do
  let(:klass) { Stagehand::Staging::CommitEntry }
  let(:source_record) { SourceRecord.create }
  subject { source_record; Stagehand::Staging::CommitEntry.last }

  describe '::matching' do
    it 'returns a list of entries that match the given source_record' do
      expect(klass.matching(source_record)).to contain_exactly(subject)
    end

    it 'returns a list of entries that match the given CommitEntry' do
      other_entry = subject.dup
      other_entry.save
      expect(klass.matching(subject)).to contain_exactly(subject, other_entry)
    end

    it 'returns a list of entries that match the given array of source records' do
      expect(klass.matching([source_record])).to contain_exactly(subject)
    end

    it 'returns an empty array if given an empty array' do
      source_record
      expect(klass.matching([])).to be_empty
    end

    it 'returns an empty array if given a nil' do
      source_record
      expect(klass.matching(nil)).to be_empty
    end

    it 'returns matching control operations' do
      start_operation = klass.start_operations.create(:commit_id => 1)
      end_operation = klass.end_operations.create(:commit_id => 1)
      expect(klass.matching([start_operation, end_operation])).to include(start_operation, end_operation)
    end
  end

  describe '#valid?' do
    it 'is false if an record_id is present without a table_name' do
      expect { subject.table_name = nil }.to change { subject.valid? }.to(false)
    end

    it 'is false if an table_name is present without a record_id' do
      expect { subject.record_id = nil }.to change { subject.valid? }.to(false)
    end
  end

  describe '#record_class' do
    subject { klass.last }
    context 'on an entry referencing a table used by multiple models' do
      it 'returns the class used to create the entry if it was a descendant STI model' do
        record = STISourceRecord.create
        expect(subject.record_class).to eq(record.class)
      end

      it 'returns the class used to create the entry if it was a root STI model' do
        record = SourceRecord.create
        expect(subject.record_class).to eq(record.class)
      end

      it 'returns the class used to create the entry if it was a root STI model' do
        record = SourceRecord.create
        expect(subject.record_class).to eq(record.class)
      end

      it 'raises an exception if the record class could not be determined from the table_name' do
        entry = klass.create(:record_id => 1, :table_name => 'fake_table', :operation => :insert)
        expect { subject.record_class }.to raise_exception(Stagehand::MissingTable)
      end

      it 'creates a dummy class if the record class could not be determined from the table_name but the table exists' do
        subject = klass.create(:record_id => 1, :table_name => 'habtm_records', :operation => :insert)
        expect(subject.record_class.name).to eq('Stagehand::DummyClass::HabtmRecord')
      end
    end
  end

  describe '#record' do
    it 'can load records from dummy classes' do
      ActiveRecord::Base.connection.execute('INSERT INTO habtm_records VALUES ()')
      subject = Stagehand::Staging::CommitEntry.last
      expect(subject.record).to be_a(Stagehand::DummyClass::HabtmRecord)
    end

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

      it 'returns an object with the same class as the production record' do
        expect(subject.record).to be_a(source_record.class)
      end

      it 'returns an object whose attributes are populated by the production record' do
        expect(subject.record).to have_attributes(source_record.attributes)
      end

      it 'responds correctly to destroyed?' do
        expect(subject.record.destroyed?).to be(true)
      end

      it 'raises a read_only exception when saving' do
        expect { subject.record.save }.to raise_exception(ActiveRecord::ReadOnlyRecord)
      end

      context 'when the record has a serialized data column' do
        let(:source_record) { SerializedColumnRecord.create!(tags: %w(big red truck)) }

        it 'populates serialized attributes correctly' do
          expect(subject.record).to have_attributes(source_record.attributes)
        end
      end

      context 'when the record is an STI subclass' do
        let(:source_record) { STISourceRecord.create! }

        it 'populates serialized attributes correctly' do
          expect(subject.record).to be_a(source_record.class)
        end
      end
    end
  end
end
