require 'pathname'
# Utility class for finding and reading files
class FileLoader
  def self.make_alternates alternates
    alternates.map do |value|
      value = value.to_s unless value.is_a?(String)
      raise "Cannot make wildcard with #{value.inspect}" if value['{'] or value['}']
      value.gsub(",", "\\,")
    end.join ","
  end
  # Takes an array of file extensions, and builds a wildcard
  # matching nothing or any extension in the list. eg: ["xml", "yaml"] => {,.xml,.yaml}
  def self.make_wildcard_for_extensions extensions
    return "" unless extensions.is_a?(Array) && !extensions.empty?
    "{,#{make_alternates(extensions.map { |e| e.to_s.start_with?(".") ? e : ".#{e}" })}}"
  end
  # An array of Pathname s searched when loading
  attr_accessor :search_paths
  # file_readers is a hash of { :file_extension => proc { |filename| return content(filename) } }
  def initialize search_paths, file_readers = {}
    self.search_paths = search_paths
    @readers = file_readers
    @file_cache = {}
  end
  def search_paths= new_paths
    @search_paths = new_paths ? Array(new_paths).map { |e| e.is_a?(String) ? Pathname.new(e) : e } : []
  end
  # Tried to load the specified file using every reader, starting by
  # the one provided (if any). Returns nil if the file does not exist,
  # raises if no reader returns a result.
  # 
  # NB: result is memoized with no clear possible
  def read_file name, reader = nil
    res = @file_cache[name]
    return (res || nil) unless res.nil?
    @file_cache[name] = false
    return nil unless File.exist?(name)
    reader = @readers[reader] if reader.is_a?(Symbol)
    ignored_errors = []
    (Array(reader) + @readers.values).each do |r|
      begin
        result = r.call(name)
        if result
          @file_cache[name] = result
          return result
        end
      rescue Exception => e
        ignored_errors << e
      end
    end
    raise RuntimeError, "Error reading #{name}#{ ignored_errors.empty? ? "" : ": " + ignored_errors.inspect }"
  end
  # Globs the pattern once for every search path
  # yielding the expanded path if Pathname
  # responds true to the pathname_test symbol.
  #
  # Returns a list of attempted paths
  def each_existing_path pattern, pathname_test = :exist?, &blk # :yields: corresponding_pathname
    attempts = []
    raise "No paths to search for #{pattern}" if @search_paths.nil? || @search_paths.empty?
    @search_paths.each do |path|
      path = (path + pattern).expand_path
      matches = Array(Pathname.glob(path).select(&pathname_test))
      attempts << path.to_s
      matches.each(&blk)
    end
    attempts
  end
  # Globs the pattern for each search path
  # yielding the expanded path and the read
  # content of the path for each readable file.
  # 
  # guessed_format is the key of the readers to try first,
  # it is inferred from the file extension if absent
  def each_existing_readable pattern, guessed_format = nil, &block # :yields: path, parsed_content
    each_existing_path(pattern, :readable?) do |path|
      guess_ext = guessed_format || path.extname.sub(".", "").downcase.to_sym
      content = read_file path, guess_ext
      yield path, content if content
    end
  end
  # Adds a wildcard for each reader's extension to basename
  # and call each_existing_readable
  def each_readable_with_basename basename, &block # :yields: path, parsed_content
    each_existing_readable("#{basename}#{FileLoader::make_wildcard_for_extensions(@readers.keys)}", nil, &block)
  end
end
