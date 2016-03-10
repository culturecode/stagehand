require 'rails_helper'

describe Stagehand::Production do
  subject { Stagehand::Production }
  let(:source_record) { SourceRecord.create }

  describe '::environment=' do
    it 'sets the environment variable for this module' do
      subject.environment = 'test'
      expect(subject.environment).to eq('test')
    end
  end

  describe '::environment' do
    it 'raises an exception if the production environment is not set' do
      subject.environment = nil
      expect { subject.environment }.to raise_exception(Stagehand::ProductionEnvironmentNotSet)
    end
  end

  describe '::status' do
    it 'returns :new if the record does not exist in the production database' do
      expect(subject.status(source_record)).to eq(:new)
    end

    it 'returns :modified if the record exists in the production database, but its attributes are different' do
      Stagehand::Production.save(source_record)
      source_record.update_attribute(:updated_at, 10.days.from_now)
      expect(subject.status(source_record)).to eq(:modified)
    end

    it 'returns :not_modified if the record exists in the production database and its attributes are the same' do
      Stagehand::Production.save(source_record)
      expect(subject.status(source_record)).to eq(:not_modified)
    end
  end

  describe '::lookup' do
    it 'returns an ActiveRecord::Relation' do
      expect(subject.lookup(source_record)).to be_a(ActiveRecord::Relation)
    end

    it 'includes only production records that match the given staging record' do
      production_record_1 = subject.save(SourceRecord.create)
      production_record_2 = subject.save(source_record)
      production_record_3 = subject.save(SourceRecord.create)

      expect(subject.lookup(source_record)).to contain_exactly(production_record_2)
    end

    it 'does not return records that have not been saved to the production database' do
      expect(subject.lookup(source_record)).to be_empty
    end
  end

  shared_examples_for 'a saved record' do
    it 'returns the new record' do
      expect(subject.save(source_record)).to be_a(Stagehand::Production::Record)
    end

    it 'saves the new record to the production database' do
      expect(subject.save(source_record).class.connection).not_to eq(source_record.class.connection)
    end

    it 'persists the record' do
      expect(subject.save(source_record)).to be_persisted
    end

    it 'does not the record' do
      expect(subject.save(source_record)).to be_persisted
    end

    it 'uses the same id as the source record' do
      expect(subject.save(source_record).id).to eq(source_record.id)
    end

    it 'makes an exact copy of the attributes' do
      source_record.update_attributes(:name => 'test')
      source_record.reload # reload ensures timestamps are only as accurate as the database can store
      expect(subject.save(source_record).attributes).to eq(source_record.attributes)
    end

    it 'writes the new record to the same table in the production database' do
      expect(subject.save(source_record).class.table_name).to eq(source_record.class.table_name)
    end

    it 'does set timestamps' do
      source_record.update_attributes(:created_at => nil, :updated_at => nil)
      expect(subject.save(source_record)).to have_attributes(:created_at => nil, :updated_at => nil)
    end

    it 'does not change timestamps' do
      source_record.update_attributes(:created_at => 1.day.ago, :updated_at => 0.5.days.ago)
      expect(subject.save(source_record)).to have_attributes(source_record.attributes.slice(:created_at, :updated_at))
    end
  end

  context 'when the record does not yet exist in the production database' do
    describe '::save' do
      it_behaves_like 'a saved record'
    end
  end

  context 'when the record exists in the production database' do
    let!(:live_record) { subject.save(source_record) }

    describe '::save' do
      it_behaves_like 'a saved record'

      it 'can update the existing record' do
        source_record.update_attributes(:name => 'changed')
        expect { subject.save(source_record) }.to change { live_record.reload.name }.to('changed')
      end
    end

    describe '::delete' do
      it 'removes the source record from the production database when given a record' do
        subject.delete(source_record)
        expect(live_record.class.where(:id => live_record)).not_to exist
      end

      it 'removes the source record from the production database when given an id and table name' do
        subject.delete(source_record.id, source_record.class.table_name)
        expect(live_record.class.where(:id => live_record)).not_to exist
      end
    end
  end

end
