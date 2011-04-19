class Bundle
  attr_reader :path, :info
  def initialize path, info
    @path = path
    @info = info
    @file_name = path.basename(".qsplugin").to_s
    @file_name = nil if @file_name == "null"
  end
  def self.bundle_info_name path
    path + "Contents/Info.plist"
  end
  def [] index
    @info[index]
  end
  def id
    @info['CFBundleIdentifier']
  end  
  def name
    self['CFBundleName'] || @file_name || id
  end
  def bundle_resources name, *attempted_extensions
    Pathname.glob(if attempted_extensions.empty?
      path + "Contents/Resources/#{name}"
    else
      path + "Contents/Resources/#{name}#{FileLoader.make_wildcard_for_extensions(attempted_extensions)}"
    end)
  end
  def inspect
    "#<#{self.class.name}:#{name}:#{self.id}:#{self.path}>"
  end
end