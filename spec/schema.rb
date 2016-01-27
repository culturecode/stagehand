
RSpec.configure do |config|
  config.before(:all) do
    # Create tables in the test and production database so we test copying from one to the other
    [:test, :production].each do |connection_name|
      ActiveRecord::Base.establish_connection connection_name

      ActiveRecord::Schema.define(:version => 0) do
        create_table :source_records, :force => true do |t|
          t.string :name
          t.timestamps :null => true
        end
      end
    end

    # Create the model
    class SourceRecord < ActiveRecord::Base
      establish_connection :test
    end
  end
end
