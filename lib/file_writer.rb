require 'pathname'
# Utility class for writing files under a specific root,
# creating folders as required, and logging the results
class FileWriter
  attr_accessor :output_root, :dry_run
  def initialize(logger, output_root)
    @output_root = Pathname.new output_root
    @dry_run = false
    @logger = logger
  end
  # Creates folders as required and yield complete output file name.
  # 
  # NB: In dry-runs, there is no yield
  def create_output_file filename # :yields: complete_filename
    output_path = @output_root + filename
    @logger.info "Writing to #{output_path}#{dry_run ? " (skipped - dry run)" : ""}" do
      unless dry_run
        folder = output_path.dirname
        folder.mkpath unless folder.directory?
        yield output_path
      end
    end
  end
  # Writes the specified content to filename, or
  # opens the file for writing and yields it if content
  # is nil.
  # 
  # NB: In dry-runs, there is no yield
  def write_to_output filename, content = nil # :yields: file
    self.create_output_file(filename) do |output_path|
      File.open(output_path, 'w') do |f|
        if content
          f.write(content)
        else
          yield f
        end
      end
    end
  end
end