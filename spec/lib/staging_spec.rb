require 'rails_helper'

describe Stagehand::Staging do
  describe '::connection_name=' do
    it 'sets the connection_name variable for this module' do
      subject.connection_name = 'test'
      expect(subject.connection_name).to eq('test')
    end
  end

  describe '::connection_name' do
    it 'raises an exception if the production connection_name is not set' do
      subject.connection_name = nil
      expect { subject.connection_name }.to raise_exception(Stagehand::StagingConnectionNameNotSet)
    end
  end
end
