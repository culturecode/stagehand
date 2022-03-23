describe Stagehand::Staging::Commit do
  let(:klass) { Stagehand::Staging::Commit }
  let(:source_record) { SourceRecord.create }

  def some_work
    SourceRecord.create
  end

  describe ':all' do
    it 'returns all commits' do
      commit_1 = klass.capture { some_work }
      commit_2 = klass.capture { some_work }
      expect(klass.all).to contain_exactly(commit_1, commit_2)
    end

    it 'does not return incomplete commits' do
      commit_1 = klass.capture { some_work }
      commit_2 = klass.capture { some_work }
      commit_3 = klass.capture { some_work }
      commit_2.entries.end_operations.delete_all
      commit_3.entries.start_operations.delete_all

      expect(klass.all).to contain_exactly(commit_1)
    end
  end

  describe '::capturing?' do
    it 'is false while not capturing' do
      expect(klass).not_to be_capturing
    end

    it 'is true while capturing' do
      klass.capture do
        expect(klass).to be_capturing
      end
    end
  end

  describe '::capture' do
    it 'commits records that were created' do
      commit = klass.capture { source_record }
      expect(commit).to include(source_record)
    end

    it 'does not include records modified outside of the block' do
      source_record
      commit = klass.capture { some_work }
      expect(commit).not_to include(source_record)
    end

    it 'does not affect the commit_id of entries for records modified outside of the block' do
      source_record
      entry = Stagehand::Staging::CommitEntry.last
      expect { klass.capture { some_work } }.not_to change { entry.reload.attributes }
    end

    it 'commits records that were updated' do
      source_record
      commit = klass.capture { source_record.increment!(:counter) }
      expect(commit).to include(source_record)
    end

    it 'commits records that were destroyed' do
      source_record
      commit = klass.capture { source_record.destroy }
      expect(commit).to include(source_record)
    end

    it 'commits records that were deleted' do
      source_record
      commit = klass.capture { source_record.delete }
      expect(commit).to include(source_record)
    end

    it 'accepts a "subject" record to indicate which record kicked off the changes in the commit' do
      commit = klass.capture(source_record) { some_work }
      expect(commit.subject).to eq(source_record)
    end

    it 'does not record the subject if it does not have an id' do
      source_record.id = nil
      commit = klass.capture(source_record) { some_work }
      expect(commit.subject).to be_nil
    end

    it 'includes the subject record' do
      commit = klass.capture(source_record) { some_work }
      expect(commit).to include(source_record)
    end

    it 'does not include the subject record if it does not have an id' do
      source_record.id = nil
      commit = klass.capture(source_record) { some_work }
      expect(commit).not_to include(source_record)
    end

    it 'raises an exception if the subject record does not have stagehand' do
      allow(source_record).to receive(:has_stagehand?).and_return(false)
      expect { klass.capture(source_record) { some_work } }.to raise_exception(Stagehand::NonStagehandSubject)
    end

    it 'allows the subject to be set during the block' do
      commit = klass.capture do |commit|
        commit.subject = source_record
      end
      expect(commit.subject).to eq(source_record)
    end

    it 'does not set the subject if during the block if the subject does not have an id' do
      commit = klass.capture do |commit|
        source_record.id = nil
        commit.subject = source_record
      end
      expect(commit.subject).to be_nil
    end

    it 'does not swallow exceptions from the given block' do
      expect { klass.capture { raise('test') } }.to raise_exception('test')
    end

    it 'ends the commit when the block raises an exception' do
      expect { klass.capture { some_work; raise } rescue nil }
        .to change { Stagehand::Staging::CommitEntry.end_operations.count }.by(1)
    end

    it 'ends the commit when the block contains a return statement' do
      def do_it
        klass.capture do
          some_work
          return
        end
      end

      expect { do_it }.to change { Stagehand::Staging::CommitEntry.end_operations.count }.by(1)
    end

    it 'does not end the commit when the block raises a Stagehand::CommitError exception' do
      expect { klass.capture { raise Stagehand::CommitError } rescue nil }
        .not_to change { Stagehand::Staging::CommitEntry.end_operations.count }
    end

    it 'does not create a commit if it contains no records' do
      expect { klass.capture { } }.not_to change { Stagehand::Staging::Commit.all.to_a }
    end

    it 'returns nil create a commit if it contains no records' do
      expect(klass.capture { }).to be_nil
    end

    it 'does not create duplicate end entries if an exception is raised while ending the commit' do
      allow(klass).to receive(:new).and_raise('an error')
      expect { klass.capture { some_work } rescue nil }
        .to change { Stagehand::Staging::CommitEntry.end_operations.count }.by(1)
    end

    it 'does not contain entries from tables in the :except option' do
      commit = klass.capture(:except => :source_records) { ConstrainedRecord.create; source_record }
      expect(commit).not_to include(source_record)
    end

    it 'contain entries from tables not in the :except option' do
      other = ConstrainedRecord.new
      commit = klass.capture(:except => :source_records) { other.save!; source_record }
      expect(commit).to include(other)
    end

    it 'contains entries from tables in the :except option if the table is the same as the subject' do
      commit = klass.capture(source_record, :except => :source_records) { source_record.increment!(:counter) }
      expect(commit).to include(source_record)
    end

    context 'if the session trigger has not been created' do
      before(:context) { Stagehand::Schema.send :drop_trigger, :stagehand_commit_entries, :insert }
      after(:context) { Stagehand::Schema.send :create_session_trigger }

      it 'raises an exception if the commit session is not set' do
        expect { klass.capture { some_work } }.to raise_exception(Stagehand::BlankCommitEntrySession)
      end
    end

    context 'when the commit is part of a transaction' do
      it 'does not leave an incomplete commit if the transaction is rolled back without an exception' do
        ActiveRecord::Base.transaction { klass.capture { ActiveRecord::Base.connection.exec_rollback_db_transaction } }
        expect { klass.all }.not_to raise_exception
      end

      it 'does not leave an incomplete commit if the transaction is rolled back with an ActiveRecord::Rollback exception' do
        ActiveRecord::Base.transaction { klass.capture { raise ActiveRecord::Rollback } }
        expect { klass.all }.not_to raise_exception
      end

      it 'does not leave an incomplete commit if the transaction is rolled back with an exception' do
        ActiveRecord::Base.transaction { klass.capture { raise } } rescue nil
        expect { klass.all }.not_to raise_exception
      end
    end

    it 'sets the start timestamp' do
      expect(klass.capture { some_work }.entries.first).to have_attributes(:created_at => be_present)
    end

    it 'sets the end timestamp' do
      expect(klass.capture { some_work }.entries.last).to have_attributes(:created_at => be_present)
    end
  end

  describe '::find' do
    it 'returns the commit with the same the given id' do
      commit_1 = klass.capture { some_work }
      commit_2 = klass.capture { some_work }
      expect(klass.find(commit_2.id)).to eq(commit_2)
    end

    it 'accepts multiple ids and returns an array' do
      commit_1 = klass.capture { some_work }
      commit_2 = klass.capture { some_work }
      expect(klass.find([commit_1.id, commit_2.id])).to contain_exactly(commit_1, commit_2)
    end

    it 'ignores a nil commit id' do
      expect(klass.find(nil)).to be_nil
    end

    it 'ignores nil commit ids in arrays' do
      commit_1 = klass.capture { some_work }
      expect(klass.find([commit_1.id, nil])).to contain_exactly(commit_1)
    end
  end

  describe '::containing' do
    let!(:commit) { klass.capture { source_record } }
    let!(:other_commit) { klass.capture { SourceRecord.create } }

    it 'returns commits that contain the given commit_entry' do
      expect(klass.containing(source_record)).to include(commit)
    end

    it 'returns commits that contain the given commit_entry when there is a matching entry with no commit' do
      source_record.increment!(:counter)
      expect(klass.containing(source_record)).to include(commit)
    end

    it 'does not return commits that do not contain the given commit_entry' do
      expect(klass.containing(source_record)).not_to include(other_commit)
    end
  end

  describe '::new' do
    it 'raises CommitNotFound that tells us the start operation is not found if the start operation entry is not present' do
      commit = klass.capture { some_work }
      commit.entries.start_operations.delete_all
      expect { klass.new(commit.id) }.to raise_exception(Stagehand::CommitNotFound, /commit_start entry/)
    end

    it 'raises CommitNotFound that tells us the end operation is not found if the end operation entry is not present' do
      commit = klass.capture { some_work }
      commit.entries.end_operations.delete_all
      expect { klass.new(commit.id) }.to raise_exception(Stagehand::CommitNotFound, /commit_end entry/)
    end
  end

  describe '#commit_id' do
    subject { klass.capture { some_work } }

    it 'matches the id of the start operation' do
      subject
      start_operation = Stagehand::Staging::CommitEntry.start_operations.last
      expect(subject).to have_attributes(:id => start_operation.id)
    end

    it 'is not affected by the order the database returns commit entries' do
      Stagehand::Staging::CommitEntry.order(:id => :asc).scoping do
        subject
      end

      Stagehand::Staging::CommitEntry.order(:id => :desc).scoping do
        expect(klass.new(subject.id)).to have_attributes(:id => subject.id)
      end
    end
  end

  describe '#entries' do
    it 'returns insert operations' do
      commit = klass.capture { source_record }
      expect(commit.entries).to include( be_insert_operation )
    end

    it 'returns update operations' do
      commit = klass.capture { source_record.increment!(:counter) }
      expect(commit.entries).to include( be_update_operation )
    end

    it 'returns delete operations' do
      commit = klass.capture { source_record.delete }
      expect(commit.entries).to include( be_delete_operation )
    end

    it 'returns start operations' do
      commit = klass.capture { source_record.increment!(:counter) }
      expect(commit.entries).to include( be_start_operation )
    end

    it 'returns end operations' do
      commit = klass.capture { source_record.increment!(:counter) }
      expect(commit.entries).to include( be_end_operation )
    end
  end

  describe '#subject' do
    it 'returns the record of the start entry' do
      expect(klass.capture(source_record) { some_work }.subject).to eq(source_record)
    end
  end

  describe '#empty?' do
    subject { klass.capture { source_record } }

    it 'is empty if the commit has no content operatings' do
      subject.entries.content_operations.delete_all
      expect(subject).to be_empty
    end

    it 'is not empty if the commit has content operations' do
      expect(subject).not_to be_empty
    end
  end

  describe 'equality' do
    subject { klass.capture { some_work } }
    let(:other) { klass.capture { some_work } }

    it 'is not equal to another commit' do
      expect(subject).not_to eq(other)
    end

    it 'is equal to another commit if the ids match' do
      allow(other).to receive(:id).and_return(subject.id)
      expect(subject).to eq(other)
    end

    it 'remove duplicates from an array using uniq' do
      allow(other).to receive(:id).and_return(subject.id)
      expect([subject, other].uniq).to contain_exactly(subject)
    end
  end

  describe 'database transaction' do
    let(:source_record) { SourceRecord.create }

    it 'records entries correctly if the transaction is contained in the capture block' do
      commit = klass.capture do
        ActiveRecord::Base.transaction do
          source_record.increment!(:counter)
        end
      end

      expect(commit).to include(source_record)
    end

    it 'rollback removes entries if the transaction is contained in the capture block' do
      commit = klass.capture do
        some_work

        ActiveRecord::Base.transaction do
          source_record.increment!(:counter)
          raise ActiveRecord::Rollback
        end
      end

      expect(commit).not_to include(source_record)
    end

    it "does not deadlock if Thread 2 deletes entries it created between the start and end entries of Thread 1's commit, after that commit has attempted to finalize" do
      @t1_started_commit = false
      @t2_written_entries = false
      @t1_ended_commit = false

      t1 = Thread.new do
        klass.capture do
          @t1_started_commit = true
          sleep 0.1 until @t2_written_entries
        end
        @t1_ended_commit = true
      end

      t2 = Thread.new do
        ActiveRecord::Base.transaction do
          record = SourceRecord.create
          entries = Stagehand::Staging::Checklist.new(record).affected_entries
          @t2_written_entries = true
          sleep 0.1 until @t1_ended_commit
          Stagehand::Staging::CommitEntry.delete(entries)
        end
      end

      expect(t1.join(10) && t2.join(10)).to be_truthy
    end
  end
end
