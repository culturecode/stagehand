describe 'ActiveRecordExtensions' do
  let(:source_record) { SourceRecord.create }

  describe '#synced?' do
    it 'returns false when there are unsynced changes' do
      expect(source_record.synced?).to be(false)
    end

    it 'returns true when there are no unsynced changes' do
      Stagehand::Staging::Synchronizer.sync_record(source_record)
      expect(source_record.synced?).to be(true)
    end
  end
end
