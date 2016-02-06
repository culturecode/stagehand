require "rails_helper"

describe Stagehand::ControllerHelper, :type => :helper do
  let(:source_record) { SourceRecord.create }
  let(:other_record) { SourceRecord.create }

  let(:commit_1) { helper.commit_staging_changes_for(source_record) { source_record.touch } }
  let(:commit_2) { helper.commit_staging_changes_for(other_record) { other_record.touch } }

  describe "#commit_staging_changes_for" do
    before { commit_1; commit_2; }

    it "commits entries under an identifier unique to the given record" do
      commit_1_identifiers = commit_1.entries.pluck(:commit_identifier)
      commit_2_identifiers = commit_2.entries.pluck(:commit_identifier)

      expect(commit_1_identifiers).not_to include(commit_2_identifiers)
    end
  end
end
