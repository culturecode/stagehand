require 'rails_helper'

describe Stagehand::Production do
  before { Stagehand::Production.environment = :production }

  let(:source_record) { SourceRecord.create }

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

    describe '::destroy' do
      it 'removes the source record from the production database when given a record' do
        subject.destroy(source_record)
        expect(live_record.class.where(:id => live_record)).not_to exist
      end

      it 'removes the source record from the production database when given an id and table name' do
        subject.destroy(source_record.id, source_record.class.table_name)
        expect(live_record.class.where(:id => live_record)).not_to exist
      end
    end
  end

end
