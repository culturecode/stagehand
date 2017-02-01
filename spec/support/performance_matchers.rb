require 'benchmark'

RSpec::Matchers.define :take_less_than do |n|
  chain :seconds do; end

  match do |block|
    @elapsed = Benchmark.realtime do
      block.call
    end
    @elapsed <= n
  end

  def supports_block_expectations?
    true
  end

  failure_message do
    "expected to run in no more than #{expected} seconds but took #{@elapsed} seconds"
  end
end
