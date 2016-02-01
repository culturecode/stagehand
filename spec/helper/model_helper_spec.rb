describe '#publish' do
  # record => hm:t => unpublished
  it 'publishes an unpublished record related with a hm:t association'

  # record => [changed, unchanged, changed]
  it 'republishes hm association records whose attributes have changed'

  it 'deletes associated hm:t join records if they no longer exist in staging'
end
