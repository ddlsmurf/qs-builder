class Hash
  # Replacing the to_yaml function so it'll serialize hashes sorted (by their keys)
  #
  # Original function is in /usr/lib/ruby/1.8/yaml/rubytypes.rb
  def to_yaml( opts = {} )
    YAML::quick_emit( object_id, opts ) do |out|
      out.map( taguri, to_yaml_style ) do |map|
        items = nil
        begin
          items = (sort { |a, b| a.inspect <=> b.inspect}).to_a
          #items = sort.to_a
        rescue ArgumentError => e
          items = enum_for(:each)
        end
        items.each do |k, v|
          map.add( k, v )
        end
      end
    end
  end
end
