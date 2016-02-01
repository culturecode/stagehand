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

  describe "#staging_changes_for" do
    before { commit_1; commit_2; }

    it "returns entries commitd under an identifier unique to the given record" do
      commit = staging_changes_for(source_record)

      expect(commit).to include(source_record)
      expect(commit).not_to include(other_record)
    end
  end

  describe '#subcommits_of' do
    before { commit_1; commit_2; }

    it 'returns all commits whose identifier appears in the entries of the given commit' do
      parent_commit = helper.commit_staging_changes_for(SourceRecord.create) do
        other_record.touch
        source_record.touch
      end

      expect(helper.subcommits_of(parent_commit)).to contain_exactly(commit_1, commit_2)
    end

    it 'does not include commits with the same identifier as the starting commit' do
      parent_commit = helper.commit_staging_changes_for(source_record) do
        other_record.touch
        source_record.touch
      end

      expect(helper.subcommits_of(parent_commit)).to contain_exactly(commit_2)
    end
  end

  describe '#commit_entry_subtree' do
    it 'returns entries from any commit the descends from the given commit' do
      record_3 = SourceRecord.create
      commit_0 = helper.commit_staging_changes_for(SourceRecord.create) do
        other_record.touch
      end

      commit_1 = helper.commit_staging_changes_for(other_record) do
        other_record.touch
        source_record.touch
      end

      commit_2 = helper.commit_staging_changes_for(source_record) do
        source_record.touch
        record_3.touch
      end
    end
  end
end
