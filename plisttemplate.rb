#!/usr/bin/env ruby
begin
  %w[plist erb tilt pathname pp optparse shellwords yaml media_wiki].
  each { |e| require e }
rescue LoadError => e
  retry if require 'rubygems'
  raise
end

$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '.')))
require "lib/file_loader"
require "lib/bundle_loader"
require "lib/hash_extensions"
require "helpers/helpers"
require "helpers/media_wiki_helpers"
require "helpers/qs_helpers"
require "yaml"

QS_BUNDLE_ID = "com.blacktree.Quicksilver"

$KCODE = 'UTF-8'

class PluginLoader < BundleLoader
  @@readers = nil
  
  def initialize options
    @@readers ||= {
      :yaml => proc { |filename| File.open(filename) { |file| YAML.load(file) } },
      :plist => proc do |filename|
        contents = nil
        File.open(filename) { |f| contents = f.read() }
        result = Plist::parse_xml(contents)
        unless result
          contents = `plutil -convert xml1 -o - #{Shellwords.shellescape(filename)}`
          result = Plist::parse_xml(contents)
        end
        raise "Unable to parse plist in from #{filename}." unless result
        result
      end
    }
    super options[:plugin_paths], @@readers
    @overrides = FileLoader.new(options[:overrides], @@readers)
    @opt = options
    @registry = nil
    @@merge_policy = HashExtensions.make_deep_merge_policy 'ID'
  end

  def load_bundle bundle_path
    result = super
    if result
      puts "Loaded #{bundle_path}"
    end
    result
  end
end

class PluginInfoLoader
  def initialize options
    @opt = options
    @bundles = {}
    @registry = nil
    @@merge_policy = lambda do |key, old_val, new_val|
      return new_val if old_val.nil?
      return old_val if new_val.nil?
      if old_val.is_a?(Array)
        if new_val.is_a?(Array)
          if old_val.all? { |e| e['ID'] }
            old_items_by_id = {}
            new_items_by_id = {}
            old_val.each { |entry| old_items_by_id[entry['ID']] = entry }
            new_val.each { |entry| new_items_by_id[entry['ID']] = entry }
            old_items_by_id.merge!(new_items_by_id, &@@merge_policy)
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
          old_val.merge!(new_val, &@@merge_policy)
        else
          raise "Cannot merge #{key}, incompatible types: #{old_val.inspect} and #{new_val.inspect}"
        end
        old_val
      else
        new_val
      end
    end
  end
  def load_overrides_for_id id
    result = {}
    @opt[:override_paths].each do |path|
      {
        "plist" => lambda { |file_path| Plist::parse_xml(file_path) },
        "yaml" => lambda { |file_path| File.open(file_path) { |file| YAML.load(file) } }
      }.each_pair do |extension, loader|
        item = Pathname.new(path) + "#{id}.#{extension}"
        item = item.realpath if item.exist?
        hash = item.exist? ? loader.call(item.to_s) : nil
        if hash && hash.is_a?(Hash)
          $stderr.puts "Merging with overrides from #{item.to_s}" if @opt[:verbose]
          result.merge!(hash, &@@merge_policy)
        end
      end
    end
    result
  end
  def reading_error path
    return "" unless @opt[:verbose]
    File.exists?(path) ?
    "\n\t  (I only understand xml plists, and hate encoding errors, so if you dont mind looking into this: " +
    "\n\t   - check with:   iconv -t utf-8 '#{path}'" +
    "\n\t   - edit with:    ${EDITOR:-mate} '#{path}'" +
    "\n\t   - convert with: plutil -convert xml1 '#{path}'" +
    "\n\t  )" : ""
  end
  def load_override_localisations id
    result = {}
    @opt[:languages].reverse.each do |lang|
      overrides = load_overrides_for_id("#{lang}/#{id}")
      result.merge!(overrides, &@@merge_policy) if overrides
    end
    result
  end
  def load_localisations id, path
    lang_rx = @opt[:languages].map { |e| /.*?\/#{e}\.lproj\/.*/i }
    result = {}
    path = Pathname.new(path + "Contents/Resources/")
    { 'QSAction' => ['name', 'commandFormat', 'description'],
      'QSObjectSource' => ['name'],
      'QSCatalogPreset' => ['name']
    }.each_pair do |root_key, properties|
      properties.each do |property_name|
        picked_file = nil
        files = Dir[path + "*.lproj/#{root_key}.#{property_name}.strings"]
        if !files.empty?
          lang_rx.each do |lang|
            picked_file = files.select { |e| lang =~ e.to_s }.first
            break if picked_file
          end
          picked_file = files.first unless picked_file
        end
        picked_file = path + "#{root_key}.#{property_name}.strings" unless picked_file
        if picked_file && File.exists?(picked_file.to_s)
          $stderr.puts "Using localisations from #{picked_file.inspect}" if @opt[:verbose]
          begin
            values = Plist::parse_xml(picked_file.to_s)
            raise "No data read" unless values && values.is_a?(Hash)
            root_key_name = root_key
            case root_key
            when "QSAction"
              root_key_name = "QSActions" # =(
            end
            values.each_pair { |k, v| ((result[root_key_name] ||= {})[k] ||= {})[property_name] = v }
          rescue Exception => e
            $stderr.puts "Error: Reading localisation in '#{picked_file}': #{e}.#{reading_error(picked_file.to_s)}"
          end
        end
      end
    end
    result.merge!(load_override_localisations(id), &@@merge_policy)
    result
  end
  def find_with_mdutil id
    # You're not supposed to use Shellwords.shellescape in quotes... hope that's ok... Bundlenames shouldn't pose a problem, but a malicious plist...
    raise "Must make find_with_mdutil safe before using it elsewhere" unless id =~ /^[a-z0-9\.-_]+$/
    `mdfind 'kMDItemContentType == "com.apple.application-bundle" && kMDItemCFBundleIdentifier == "#{Shellwords.shellescape(id)}"'`.split("\n").first
  end
  def load_quicksilver_plists path
    result = {}
    %w[ResourceLocations QSKindDescriptions].each do |plist|
      res_path = path + "Contents/Resources/#{plist}.plist"
      if res_path.file?
        $stderr.puts "Using Quicksilver ressource #{res_path.to_s.inspect}" if @opt[:verbose]
        begin
          values = Plist::parse_xml(res_path.to_s)
          (result[plist] ||= {}).merge!(values, &@@merge_policy)
        rescue Exception => e
          $stderr.puts "Error: Reading Quicksilver ressource in '#{res_path}': #{e}.#{reading_error(res_path.to_s)}"
        end
      end
    end
    result
  end
  def load_global_data id = QS_BUNDLE_ID
    quicksilver_path = @opt[:qs_app_path] || find_with_mdutil(id)
    quicksilver_path = Pathname.new(quicksilver_path).expand_path if quicksilver_path
    result = load_quicksilver_plists(quicksilver_path)
    $stderr.puts "Warning: Nothing loaded from Quicksilver.app. Check path: #{quicksilver_path.inspect}" if result.empty?
    overrides = load_overrides_for_id(id)
    result.merge!(overrides, &@@merge_policy) if overrides
    result.merge!(load_override_localisations(id), &@@merge_policy)
    @bundles[id] = result
    result
  end
  def load_qsplugin path
    path = Pathname.new(path) unless path.is_a?(Pathname)
    path = path.realpath if path.exist?
    begin
      if !path.directory?
        raise "Couldnt find #{path}!"  if @opt[:verbose]
        return nil
      end
      $stderr.puts "Loading #{path}" if @opt[:verbose]
      result = Plist::parse_xml(path + 'Contents/info.plist')
      id = result["CFBundleIdentifier"]
      if result && id
        result["QSModifiedDate"] = path.stat.mtime.strftime("%Y-%m-%d %H:%M:%S %z")
        result.merge!(self.load_overrides_for_id(id), &@@merge_policy)
        result.merge!(self.load_localisations(id, path), &@@merge_policy)
        $stderr.puts "More that one plugin with same ID, second at #{path}" if @opt[:verbose] && @bundles[id]
        @bundles[id] = result
        return result
      end
    rescue Exception => e
      $stderr.puts "Warning: #{e}#{@opt[:verbose] ? reading_error(path) : ""}"
      raise if @opt[:debug]
    end
    return nil
  end
  attr_reader :registry
  def build_registry
    @registry = {}
    resources = @registry['QSResourceAdditions'] = {}
    @bundles.each_pair do |id, bundle|
      bundle = YAML.load(bundle.to_yaml) #yuk
      reg = bundle['QSRegistration']
      if reg
        reg.each_pair do |name, val|
          val.values.each { |e| e[:provided_by] = id } if val.values.all? { |e| e.is_a?(Hash) }
        end
        @registry.merge!({'QSRegistration' => reg}, &@@merge_policy)
      end
      res = bundle['QSResourceAdditions']
      if res
        res.each_pair do |k, v|
          $stderr.puts "Warning: Resource is defined twice: #{resources[k].inspect} and #{v.inspect}" if resources[k]
          v = v.dup
          v[:provided_by] = id if v.is_a?(Hash)
          resources[k] = v
        end
        @registry.merge!({'QSResourceAdditions' => res}, &@@merge_policy)
      end
    end
  end
  def load name
    @opt[:plugin_paths].map do |path|
      item = Pathname.new(path) + name
      item = item.realpath if item.exist?
      item = Pathname.new(path) + "#{name}.qsplugin" unless item.directory?
      item = item.realpath if item.exist?
      result = self.load_qsplugin(item)
      return result if result
    end
    return nil
  end
  def load_all
    result = []
    @opt[:plugin_paths].map do |path|
      item = Pathname.new(path)
      item = item.realpath if item.exist?
      plugins = Dir[item + "*.qsplugin"]
      result += plugins.map { |e| load_qsplugin(e) }.select {|e| e}.to_a
    end
    build_registry
    result
  end
end

module RenderingHelpers
  def app
    App.shared
  end
  def quicksilver_bundle
    app.quicksilver_bundle
  end
  @@template_path = nil
  def load_template name
    result = (@@templates ||= {})[name.to_s]
    return result if result
    name = name.to_s
    file_name = (@@template_path || ".") + "/" + name
    if !File.exist?(file_name)
      matches = Dir[file_name + ".*"]
      raise "Error loading template #{name} from #{file_name} (#{matches.count} matches)" if matches.count != 1
      file_name = matches[0]
    end
    @@template_path ||= File.dirname(file_name.to_s)
    @@templates[name.to_s] = Tilt.new(file_name.to_s, :trim => "<>")
  end
  def set_template_path path, clear = true
    @@template_path = path
    @@templates = {} if clear
  end
  def render_depth substract = 0
    result = 0
    cursor = self
    while cursor.parent
      cursor = cursor.parent
      result += 1
    end
    result - substract
  end
  def render name, item, locals = {}
    template = load_template(name)
    item = RenderContext.new(item, self) if item.is_a?(Hash)
    template.render(item, locals)
  end
  def partial name, item, locals = {}
    render("partials/_#{name}", item, locals)
  end
end
class RenderContext
  include Helpers
  include RenderingHelpers
  include MediaWikiHelpers
  include QSLinkHelpers
  include QSHelpers
  def initialize hash, parent = nil
    @vals = {}
    @parent = parent
    hash.each_pair { |name, val| @vals[name] = val } if hash
  end
  attr_reader :parent
  def [](index)
    result = @vals[index.to_s]
    return RenderContext.new(result, self) if result && result.is_a?(Hash)
    result
  end
  def method_missing(meth, *args, &blk)
    result = self[meth.to_s]
    if !result && @vals.respond_to?(meth)
      @vals.send(meth, *args, &blk)
    else
      result
    end
  end
end
class App
  @@default = nil
  def self.shared
    @@default
  end
  def initialize(options = {})
    @options = options
    raise "Cannot have more than one App" if @@default
    @@default = self
  end
  attr_reader :options, :bundles, :quicksilver_bundle
  def parse_options
    args = OptionParser.new do |opts|
      opts.banner = "Usage: plisttemplate.rb [options] [plugin base name]"

      opts.on("--out PATH", "Prefix all output files to specified path") do |v|
        @options[:output] = v
      end

      opts.on("-o", "--override-path PATH", "Add path containing override plists") do |v|
        @options[:override_paths] << v
      end

      opts.on("--plist NAME", "Write a plist stream of the plugins to the specified filename") do |v|
        @options[:templates] << "plist"
        @options[:plist] = v
      end

      opts.on("-p", "--plugin-search-path PATH", "Add path containing .qsplugin folders") do |v|
        @options[:plugin_paths] << v
      end

      opts.on("-l", "--languages en,fr,de,it", "Set languages to try and use when multiple are available") do |v|
        @options[:languages] = v.split(/[^a-z-]+/i)
      end

      opts.on("-t", "--templates FILEPATH", "Add template to run. Must contain an init.rb file.") do |v|
        @options[:templates] << v
      end

      opts.on("--wiki-prefix PREFIX", "Add prefix to all local wiki links when creating Page name") do |v|
        @options[:wiki_prefix] = v
      end

      opts.on("--qs-path PATH", "Set the path to Quicksilver.app from which load resources") do |v|
        @options[:qs_app_path] = v
      end

      opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        @options[:verbose] = v
      end
      opts.on("-d", "--[no-]debug", "Output debug information") do |v|
        @options[:debug] = v
        @options[:verbose] = v if v
      end
    end
    begin
      args.parse!
    rescue Exception => e
      $stderr.puts("Error in the arguments: #{e}\n\n")
      $stderr.puts(args)
      exit 1
    end

    if @options[:plugin_paths].empty?
      @options[:plugin_paths] += ['~/Library/Application Support/Quicksilver/PlugIns',
        '/Applications/Quicksilver.app/Contents/PlugIns/'].map { |e| Pathname.new(e).expand_path }
    end
  end
  def run_template(name)
    template_init = (Pathname.new(name) + 'init.rb').expand_path
    if template_init.file?
      require template_init.to_s.gsub(/.rb$/i, "")
    end
  end
  def run
    parse_options
    @loader = PluginInfoLoader.new @options
    @quicksilver_bundle = @loader.load_global_data
    @bundles = []
    raise "You need to specify which plugins to generate on the command line. If you really want to generate all, specify '*'" if ARGV.count == 0
    raise "Must specify at least one template, eg: -t basic or --plist plugins.xml" if @options[:templates].empty?
    @bundles = ARGV == ["*"] ? @loader.load_all : ARGV.map { |e| @loader.load(e) }
    if !File.directory?(@options[:output])
      FileUtils::makedirs(@options[:output])
      raise "Directory '#{@options[:output]}' doesn't exist" if !File.directory?(@options[:output])
    end
    @bundles.each_with_index do |input, index|
      raise "Couldn't find plugin (#{ARGV[index] || "<unidentifiable>"})#{@options[:verbose] ? "" : " (run with verbose: -v to see search paths)"}" if input.nil?
    end
    @options[:templates].each { |t| run_template(t) }
  end
  def registry
    @loader.registry
  end
  def write_to_output(filename, contents)
    output_path = @options[:output] + "/" + filename
    puts "Writing output to #{output_path}" if options[:verbose]
    File.open(output_path, 'w') {|f| f.write(contents) }
  end
end
App.new({
  :plugin_paths => [],
  :override_paths => [],
  :languages => ['en'],
  :output => './',
  :plist => "plugins.plist",
  :templates => [],
}).run

