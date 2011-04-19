module HashExtensions
  def self.dup_structure object, &block
    case object
    when Hash
      result = {}
      object.each_pair { |name, val| result[name] = dup_structure(val, &block) }
      object = result
    when Array
      object = object.map { |val| dup_structure(val, &block) }
    else
      object = object.dup_structure(&block) if object.respond_to?(:dup_structure)
    end  
    object = block.call(object) if block
    object
  end
  def self.deep_schema object, &block
    case object
    when Hash
      result = {}
      object.each_pair do |name, val|
        name = deep_schema(name, &block) unless val.is_a?(Hash) || val.is_a?(Array)
        result[name] = deep_schema(val, &block)
      end
      object = result
    when Array
      object = object.map { |val| deep_schema(val, &block) }
      object = ["*#{object.first.inspect}".to_sym] if !object.empty? && object.reduce { |a, b| a == b ? a : nil }
    else
      object = object.class.name.to_sym
    end
    object = block.call(object) if block
    object
  end
  def self.make_deep_merge_policy id_key, &block
    resulting_policy =
     lambda do |key, old_val, new_val|
      return new_val if old_val.nil?
      return old_val if new_val.nil?
      if old_val.is_a?(Array)
        if new_val.is_a?(Array)
          if id_key && old_val.all? { |e| e[id_key] }
            old_items_by_id = {}
            new_items_by_id = {}
            old_val.each { |entry| old_items_by_id[entry[id_key]] = entry }
            new_val.each { |entry| new_items_by_id[entry[id_key]] = entry }
            old_items_by_id.merge!(new_items_by_id, &resulting_policy)
            old_val = old_items_by_id.values
          else
            old_val += new_val
          end
        else
          raise "Cannot merge #{key}, incompatible types: #{old_val.inspect} and #{new_val.inspect}"
        end
        old_val
      elsif old_val.is_a?(Hash)
        if new_val.is_a?(Hash)
          old_val.merge!(new_val, &resulting_policy)
        else
          raise "Cannot merge #{key}, incompatible types: #{old_val.inspect} and #{new_val.inspect}"
        end
        old_val
      else
        new_val = block.call(key, old_val, new_val) if block
        new_val
      end
    end
  end
end
