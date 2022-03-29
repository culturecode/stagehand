describe Stagehand::Auditor do
  describe '::incomplete_commits' do
    it "returns a hash with commit ids as keys, and arrays of incomplete commit's entries as values"

    it 'includes commits without end operations' do
      commit = Stagehand::Staging::Commit.capture { SourceRecord.create }
      commit.entries.last.delete

      expect(subject.incomplete_commits.keys).to contain_exactly(commit.id)
    end

    it 'includes commits without start operations' do
      commit = Stagehand::Staging::Commit.capture { SourceRecord.create }
      commit.entries.first.delete

      expect(subject.incomplete_commits.keys).to contain_exactly(commit.id)
    end
  end

  describe '::mismatched_records' do
    without_transactional_fixtures # Must set up preconditions outside transaction they can be seen from other connections

    let(:source_record) { SourceRecord.create }

    it 'includes records that appear in staging but not in production' do
      source_record
      expect(subject.mismatched_records[SourceRecord.table_name]).to include(source_record.id)
    end

    it 'includes records that appear in production but not in staging' do
      Stagehand::Production.save(source_record)
      source_record.delete
      expect(subject.mismatched_records[SourceRecord.table_name]).to include(source_record.id)
    end

    it 'includes records whose attributes differ between production and staging' do
      Stagehand::Production.save(source_record)
      source_record.increment!(:counter)
      expect(subject.mismatched_records[SourceRecord.table_name]).to include(source_record.id)
    end

    it 'does not include records whose attributes do not differ between production and staging' do
      Stagehand::Production.save(source_record)
      expect(subject.mismatched_records[SourceRecord.table_name]).not_to include(source_record.id)
    end
  end
end
