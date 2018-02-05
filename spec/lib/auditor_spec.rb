describe Stagehand::Auditor do
  describe '::incomplete_commits' do
    let(:ce) { Stagehand::Staging::CommitEntry }
    let(:start_operation) { ce.start_operations.create }

    it "returns a hash with commit ids as keys, and arrays of incomplete commit's entries as values"

    it 'includes commits without end operations when a later start entry exists on the same session' do
      start_operation
      ce.start_operations.create

      expect(subject.incomplete_commits.keys).to contain_exactly(start_operation.id)
    end

    it 'includes commits with uncontained start operations when a later start entry exists on the same session' do
      start_operation
      ce.end_operations.create
      ce.start_operations.create


      expect(subject.incomplete_commits.keys).to contain_exactly(start_operation.id)
    end

    it 'includes commits with uncontained end operations when a later entry exists on the same session' do
      start_operation
      ce.end_operations.create
      ce.delete_operations.create

      expect(subject.incomplete_commits.keys).to contain_exactly(start_operation.id)
    end

    it 'does not include commits without end operations if no later start entry exists on the same session' do
      start_operation
      ce.delete_operations.create

      expect(subject.incomplete_commits.keys).not_to include(start_operation.id)
    end

    it 'does not include commits with uncontained end operations if no later entry exists on the same session' do
      start_operation
      ce.end_operations.create

      expect(subject.incomplete_commits.keys).not_to include(start_operation.id)
    end

    it 'does not include commits with uncontained start operations when a later start entry exists on another session' do
      start_operation
      ce.delete_operations.create
      ce.start_operations.create.update_attribute(:session, "not #{start_operation.session}")

      expect(subject.incomplete_commits.keys).not_to include(start_operation.id)
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
