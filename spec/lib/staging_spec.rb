require 'rails_helper'

describe Stagehand::Staging::Checklist do
  describe '#new' do
    it 'accepts a single ActiveRecord::Base object'
  end

  shared_examples_for 'a checklist' do
    describe 'related_records' do
      it "returns all records from the staging_record's associations, and their associated records, ad infinitum"
      it 'does not return duplicate records that appear in the same association'
      it 'does not return duplicate records that appear in different associations'
      it 'does not return duplicate records as a result of an inverse-of association'
    end

    describe '#will_stage' do
      it 'returns related_records from the staging database that do not exist in the production database'
    end

    describe '#will_delete' do
      it 'returns related_records from the production database that do not exist in the staging database'
    end

    describe '#can_stage' do
      it 'returns related_records from the production database that have been updated in the staging database'
    end
  end

  context 'when the staging_record is exists in production' do
    it_behaves_like 'a checklist'
  end

  context 'when the staging_record does not exist in production' do
    it_behaves_like 'a checklist'
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
