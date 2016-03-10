require 'rails_helper'

describe Stagehand::Staging do
  describe '::environment=' do
    it 'sets the environment variable for this module' do
      subject.environment = 'test'
      expect(subject.environment).to eq('test')
    end
  end

  describe '::environment' do
    it 'raises an exception if the production environment is not set' do
      subject.environment = nil
      expect { subject.environment }.to raise_exception(Stagehand::StagingEnvironmentNotSet)
    end
  end
end
