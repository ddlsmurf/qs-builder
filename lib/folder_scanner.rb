class FolderScanner

  DEFAULT_SKIP_FILES = [".DS_Store", "\\..*", "_svn", "Thumbs.db", "Temporary Items"]
  Options = Struct.new(*%w[recurse excluded excluded_files excluded_directories included included_files included_directories].map(&:to_sym)) do
    def parse(optionparser)
      optionparser.separator "\nFolder and file scan options"

      self.recurse = nil
      self.excluded = DEFAULT_SKIP_FILES
      self.excluded_files = nil
      self.excluded_directories = nil
      self.included = nil
      self.included_files = nil
      self.included_directories = nil

      optionparser.on('-i', '--include RX', String, "Only include files and folders that match any such regexp") { |rx| (self.included ||= []) << rx }
      optionparser.on('--include-dirs RX', String, "Only include folders that match any such regexp") { |rx| (self.included_directories ||= []) << rx }
      optionparser.on('--include-files RX', String, "Only include files that match any such regexp") { |rx| (self.included_files ||= []) << rx }
      optionparser.on('-x', '--exclude RX', String, "Exclude files and folders that match any such regexp") { |rx| (self.excluded ||= []) << rx }
      optionparser.on('--exclude-dirs RX', String, "Exclude folders that match any such regexp") { |rx| (self.excluded_directories ||= []) << rx }
      optionparser.on('--exclude-files RX', String, "Exclude files that match any such regexp") { |rx| (self.excluded_files ||= []) << rx }
      optionparser.on('-a', '--no-exclude', "Empties all the lists of exclusions") do
        self.excluded = []
        self.excluded_files = nil
        self.excluded_directories = nil
      end
      optionparser.on('-r', '--recursive', "Scan directories recursively") { self.recurse ||= -1 }
      optionparser.on("-d", "--depth N", Integer, "Set maximum recursion to N subfolders. (0=no recursion)") { |n| self.recurse = n.to_i }
    end
  end

  def include?(name, is_file)
    can_include = (@included.nil? || @included.match(name)) &&
      ((is_file && (@included_files.nil? || @included_files.match(name))) ||
       (!is_file && (@included_directories.nil? || @included_directories.match(name))))
    if can_include
      can_include = (@excluded.nil? || !@excluded.match(name)) &&
        ((is_file && (@excluded_files.nil? || !@excluded_files.match(name))) ||
         (!is_file && (@excluded_directories.nil? || !@excluded_directories.match(name))))
    end
    can_include
  end

  def scan(folder, options, visitor = nil, relative_path = "", depth = 0, &block)
    # :yields: full_path, relative_path, name, should_include, is_file
    would_recurse = @recurse == -1 || depth < @recurse
    Dir.new(folder).each do |file_name|
      unless file_name == "." || file_name == ".."
        file_path = File.join(folder, file_name)
        is_file = File.file? file_path
        is_folder = File.directory? file_path
        if is_file || is_folder
          should_include = include? file_name, is_file
          yield file_path, relative_path, file_name, should_include, is_file if block_given?
          if is_folder
            should_include = visitor.enter_folder(file_name, !(would_recurse && should_include)) if visitor
          else
            visitor.add file_name, nil, !should_include if visitor
          end
          if should_include && is_folder
            if would_recurse # Recurse with a stack instead !!!
              folder_path = relative_path != "" ? File.join(relative_path, file_name) : file_name
              scan file_path, options, visitor, folder_path, depth + 1, &block
            end
            visitor.leave_folder if visitor
          end
        end
      end
    end
  end

  def compile_regexp(rx_list)
    return nil if rx_list.nil? || rx_list.reject { |e| e.length == 0 }.empty?
    Regexp.union(*rx_list.map { |e| /\A#{e}\z/i })
  end

  def run(arguments, options, &block)
    @excluded = compile_regexp options.excluded
    @excluded_files = compile_regexp options.excluded_files
    @excluded_directories = compile_regexp options.excluded_directories
    @included = compile_regexp options.included
    @included_files = compile_regexp options.included_files
    @included_directories = compile_regexp options.included_directories
    @recurse = options.recurse || 0

    result = []
    arguments.each do |folder|
      if File.file?(folder)
        yield folder, File.dirname(folder), File.basename(folder), include?(folder, true), true
      else
        scan folder, options, &block
      end
    end
  end
end
