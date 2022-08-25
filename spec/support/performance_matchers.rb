require 'benchmark'

RSpec::Matchers.define :take_less_than do |limit|
  chain :over do |samples: nil, warmup: nil, discard_outliers: true|
    @samples = samples
    @warmup = warmup
    @discard_outliers = discard_outliers
  end

  chain :seconds do; end

  match do |block|
    @times = []
    @samples ||= 5
    @warmup ||= 1

    @warmup.times do
      block.call
    end

    @samples.times do
      @times << Benchmark.realtime(&block)
    end

    # Discard the highest and lowest times
    if @discard_outliers
      @times.sort!
      @times.pop
      @times.shift
    end

    @elapsed = @times.sum
    @elapsed / @times.length < limit
  end

  failure_message do
    "expected to run in no more than #{expected} seconds but took #{@elapsed} seconds"
  end

  def supports_block_expectations?
    true
  end
end
