require 'rails_helper'

describe Stagehand::Staging::Auditor do
  let(:ce) { Stagehand::Staging::CommitEntry }
  let(:start_operation) { ce.start_operations.create }

  describe '::incomplete_commits' do
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
end
