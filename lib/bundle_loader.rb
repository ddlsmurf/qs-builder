
require "lib/file_loader"
require "lib/bundle"
%w[pathname shellwords yaml plist].
each { |e| require e }

# Helper class for locating and loading a bundle and it's info.plist
class BundleLoader < FileLoader
  class NoBundleFound < StandardError
  end
  def initialize search_paths, readers
    super search_paths, readers
    @bundles = {}
  end
  def warn_duplicate_bundle bundle, extras
    puts "Warning duplicate bundle: #{bundle.inspect} and #{extras.map(&:inspect).join ", "}"
  end
  # Read the plist and return a Bundle at the provided path
  def load_bundle bundle_path
    result = nil
    info_dict = Bundle::bundle_info_name(bundle_path)
    if info_dict.file?
      result = Bundle.new(bundle_path, read_file(info_dict, :plist))
      prev = @bundles[result.id]
      if prev
        warn_duplicate_bundle prev, [result]
        result = nil
      else
        @bundles[result.id] = result
      end
    end
    result
  end
  # Locate a bundle in the search paths
  def find_bundles path_pattern, warn_of_duplicate_files = true
    results = []
    duplicates = []
    attempts = each_existing_path path_pattern, :directory? do |bundle_path|
      result = load_bundle bundle_path
      if result
        if warn_of_duplicate_files && !results.empty?
          duplicates << bundle_path
        else
          results << result
        end
      end
    end
    warn_duplicate_bundle(results.first, duplicates) if warn_of_duplicate_files and !duplicates.empty?
    raise NoBundleFound, "No bundle found with pattern #{path_pattern.inspect}. Searched:\n\t- #{attempts.join "\n\t- "}" if results.empty?
    results
  end
  # Locate a bundle by its ID using spotlight
  # 
  # Only kMDItemContentType s com.apple.application-bundle and searchs com.apple.systempreference.prefpane
  def find_with_mdutil id
    # You're not supposed to use Shellwords.shellescape in quotes... hope that's ok... Bundlenames shouldn't pose a problem, but a malicious plist...
    raise "Must make find_with_mdutil safe before using it elsewhere" unless id =~ /^[a-z0-9\.-_]+$/
    results = `mdfind '(kMDItemContentType == "com.apple.application-bundle" || kMDItemContentType == "com.apple.systempreference.prefpane") && kMDItemCFBundleIdentifier == "#{Shellwords.shellescape(id)}"'`.split("\n")
    raise NoBundleFound, "Could not find application/prefpane with bundle id #{id} using mkfind" if results.empty?
    warn_duplicate_bundle id, results if results.count > 1
    results[0]
  end
  protected :find_with_mdutil
  # Find or load specified ID, using spotlight to locate it
  def find_bundle_by_id id
    result = @bundles[id]
    unless result
      match = find_with_mdutil(id)
      return load_bundle(Pathname.new(match)) if match
    end
    result
  end
end