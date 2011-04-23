begin
  require 'json'
rescue LoadError => e
  retry if require 'rubygems'
  raise
end

App.register do
  def dict_readers
    { :json => proc { |filename| File.open(filename) { |file| JSON.parse(file.read()) } } }
  end
end