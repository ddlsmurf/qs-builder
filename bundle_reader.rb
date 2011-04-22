#!/usr/bin/env ruby
begin
  %w[plist erb tilt pathname pp optparse shellwords yaml].
  each { |e| require e }
rescue LoadError => e
  retry if require 'rubygems'
  raise
end

$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '.')))
require "lib/cli_logger"
require "lib/cli_app"
require "lib/file_loader"
require "lib/file_writer"
require "lib/template_writer"
require "lib/bundle"
require "lib/bundle_loader"
require "lib/hash_extensions"
require "lib/qs"
require "helpers/helpers"
require "helpers/templatedata_helpers"
require "helpers/url_helpers"

BUNDLE_RESOURCES_TO_MERGE = %w[ResourceLocations.plist QSKindDescriptions.plist QSRegistration.plist
  QSAction.name.strings QSAction.commandFormat.strings QSAction.description.strings
QSObjectSource.name.strings QSCatalogPreset.name.strings]
LANGUAGE_ALIASES = { 'en' => 'English', 'es' => 'Spanish', 'it' => 'Italian', 'de' => 'German', 'fr' => 'French'}
DEFAULTS = {
  :plugin_paths => ['~/Library/Application Support/Quicksilver/PlugIns',
  '/Applications/Quicksilver.app/Contents/PlugIns/'],
  :override_paths => [],
  :languages => ['en'],
  :output => 'out',
  :plist => "plugins.plist",
  :templates => [],
}
TILT_TEMPLATE_CONFIG = {:trim => "<>"}

class Bundle
  def keys
    @info.keys
  end
  def localisation_table table_name
    return @localisation_tables[table_name] if (@localisation_tables ||= {}).has_key?(table_name)
    result = nil
    table_name = table_name.downcase
    if self[:res]
      self[:res].each_pair do |key, val|
        if key.downcase.start_with?(table_name)
          raise "More than one localisation table starts with #{table_name.inspect}: #{self[:res].keys.inspect}" if result
          result = val
          # break # leaving this out to debug templates
        end
      end
    end
    result = result[:current] if result
    @localisation_tables[table_name] = result
    result
  end
  def localised_string table, key
    table = localisation_table table
    return nil unless table
    table[key]
  end
end

class Bundle
  @@merge_policy = HashExtensions.make_deep_merge_policy 'ID'
  def merge! hash = {}
    @original ||= HashExtensions.dup_structure(info)
    @info.merge!(hash, &@@merge_policy)
  end
end

App.register do # Support for YAML and PList formats
  def dict_readers
    @readers ||= {
      :yaml => proc { |filename| File.open(filename) { |file| YAML.load(file) } },
      :plist => proc do |filename|
        contents = nil
        File.open(filename) { |f| contents = f.read() }
        result = Plist::parse_xml(contents)
        unless result
          contents = `plutil -convert xml1 -o - #{Shellwords.shellescape(filename.to_s)}`
          result = Plist::parse_xml(contents)
        end
        raise "Unable to parse plist in from #{filename}." unless result
        result
      end
    }
  end
  def template_readers
    reader = lambda { |filename| Tilt::new(filename, nil, TILT_TEMPLATE_CONFIG) }
    result = {}
    Tilt.mappings.keys.each { |k| result[k.to_sym] = reader}
    result
  end
end

App.register do # Main application, load bundles, feed to templates
  def run arguments, global_options
    logger = App.require_one(:logger)
    logger.debug "Startup - Loading Bundles", :bundles_to_load => arguments, :config => global_options
    App.call_extension_point :load_bundles, arguments, global_options
    logger.debug "Running Templates"
    template_data = App.require_one :template_data
    App.call_extension_point :run_template, template_data
  end
end

App.register do # Loads the bundles with a PluginLoader
  # Implement to provide a new file reader that should return a hash.
  App.extension_point :dict_readers, :mediator => lambda { |a, b| a.merge(b) }

  def parse_options opts, global_options
    opts.banner = "#{opts.program_name} [options] plugins_to_process"
    opts.separator ""
    opts.separator "Bundle loading options"

    opts.on("-p", "--plugin-search-path PATH", "Add path containing .qsplugin folders") do |v|
      (global_options[:plugin_paths] ||= []) << v
    end
    opts.on("-l", "--languages en,fr,de,it", "Set languages to try and use when multiple are available") do |v|
      global_options[:languages] = v.split(/[^a-z-]+/i)
    end
    opts.on("--qs-path PATH", "Set the path to Quicksilver.app from which load resources") do |v|
      global_options[:qs_app_path] = v
    end
    opts.on("--dont-load-bundles", "Do not use mdfind to locate external bundles, use only overrides") do
      global_options[:dont_load_bundles] = true
    end
  end
  def validate_options arguments, global_options
    global_options.merge!(DEFAULTS) do |key, val, default_val|
      if !val || (val.respond_to?(:empty?) && val.empty?) || (val.respond_to?(:size) && val.size == 0)
        default_val
      else
        val
      end
    end
    raise ArgumentError, "No languages specified" if global_options[:languages].to_s == ""
    global_options[:languages] = global_options[:languages].map { |l| [l] + Array(LANGUAGE_ALIASES[l.downcase]) }.flatten
    raise ArgumentError, "No plugin name to load. If you really want to load all, specify '*'." if arguments.count == 0
  end
  def template_data
    { :bundles => @bundles, :qs => @qs_app }
  end
  def make_fake_app_bundle id
    fake_path = Pathname.new("/dev/null")
    bundle = Bundle.new fake_path, { 'CFBundleIdentifier' => id }
    App.call_extension_point :bundle_will_load, fake_path
    App.call_extension_point :bundle_did_load, bundle
    bundle
  end
  def load_external_app bundle_loader, id
    begin
      @logger.info "Loading application #{id.inspect}"
      #mdfind '(kMDItemContentType == "com.apple.application-bundle" || kMDItemContentType == "com.apple.systempreference.prefpane") && kMDItemCFBundleIdentifier == "com.apple.airport.adminutility"'
      return bundle_loader.find_bundle_by_id id
    rescue BundleLoader::NoBundleFound => e
      @logger.info "Application/PrefPane #{id} not found, faking it"
      bundle = make_fake_app_bundle id
    end
    bundle
  end
  def load_bundles bundles, global_options
    @logger = App.require_one(:logger)
    readers = App.require_one(:dict_readers)
    bundle_loader = PluginLoader.new(global_options[:plugin_paths], readers, @logger)
    @qs_app = bundle_loader.load_qs_bundle global_options[:qs_app_path]
    @bundles = QS::Registry.load_plugins(bundle_loader.load_plugins(bundles), @qs_app) do |bundle_id|
      if global_options[:dont_load_bundles]
        make_fake_app_bundle bundle_id
      else
        load_external_app bundle_loader, bundle_id
      end
    end
  end
end

class RenderContext
  include Helpers
  include URLHelpers
  include TemplateDataHelpers
end

App.register do # Template loader
  # Implement to provide a local available to the templates.
  App.extension_point :template_data, :mediator => lambda { |a, b| a.merge(b) }
  # Implement to provide template engines
  App.extension_point :template_readers, :mediator => lambda { |a, b| a.merge(b) }
  # Implemented to provide a file writing mecanism to the templates
  App.extension_point :output_writer
  def parse_options opts, global_options
    opts.separator "Template output options"
    opts.on("--out PATH", "Prefix all output files to specified path") do |v|
      global_options[:output] = v
    end
    opts.on("--plist NAME", "Write a plist stream of the plugins to the specified filename") do |v|
      (global_options[:templates] ||= []) << "plist"
      global_options[:plist] = v
    end
    opts.on("-t", "--templates FILEPATH", "Add template to run. Must contain an init.rb file.") do |v|
      (global_options[:templates] ||= []) << v
    end
    opts.on("--dry-run", "Do not actually write anything.") do |v|
      global_options[:dry_run] = true
    end
    opts.on("--wiki-prefix PREFIX", "Add prefix to all local wiki links when creating Page name") do |v|
      global_options[:wiki_prefix] = v
    end
  end
  def validate_options arguments, global_options
    raise "Must specify at least one template, eg: -t basic or --plist plugins.xml" if (global_options[:templates] || []).empty?
  end
  def output_writer
    @output_writer
  end
  def template_writer *view_paths
    TemplateWriter.new @logger, App.require_one(:output_writer), view_paths, @readers
  end
  def template_data
    { :config => @options }
  end
  def startup arguments, global_options
    @logger = App.require_one(:logger)
    global_options[:templates].uniq.each do |template|
      @logger.info "Loading template", template.inspect do
        unless App.load_extensions template
          raise ArgumentError, "Could not find template #{template.inspect}"
        end
      end
    end
    @options = global_options
    @readers = App.require_one :template_readers
    @output_writer = FileWriter.new @logger, global_options[:output]
    @output_writer.dry_run = true if global_options[:dry_run]
  end
end

App.register do # Override provider
  def parse_options opts, global_options
    opts.on("-o", "--override-path PATH", "Add path containing override plists") do |v|
      (global_options[:override_paths] ||= []) << v
    end
  end
  def validate_options arguments, global_options
    paths = global_options[:override_paths] || []
    @logger = App.require_one(:logger)
    @languages = global_options[:languages] || []
    unless paths.empty?
      @loader = FileLoader.new paths, App.require_one(:dict_readers)
    end
  end
  def merge_overrides_for bundle, id
    return unless @loader
    loaded = []
    ((@languages || []) + [nil]).reverse.each do |l|
      attempts = @loader.each_readable_with_basename("#{l ? l + "/" : ""}#{id}") do |path, content|
        loaded << path.to_s
        bundle.merge! content
      end
    end  
    @logger.debug "Loaded overrides", loaded unless loaded.empty?
  end
  def merge_languages_for bundle
    res = bundle[:res]
    return unless res
    langs = ((@languages || []) + [nil, ""]).reverse
    res.each_pair do |name, val|
      loaded_res = false
      langs.each do |language|
        entries = val[language]
        if entries
          loaded_res = true
          bundle.merge!({ :res => { name => { :current => entries }}})
          @logger.debug "Merging language #{language.nil? || language == "" ? "<neutral>" : language} of #{name} (#{entries.size} entries)"
        end
      end
      if !loaded_res
        @logger.info "No languages loaded for #{name} in #{bundle.inspect}", :available_languages => Array(val.keys)
      end
    end
  end
  def bundle_did_load bundle
    merge_overrides_for bundle, bundle.id
    merge_languages_for bundle
  end
end

class PluginLoader < BundleLoader
  def initialize search_path, readers, logger
    super search_path, readers
    @readers = readers
    @logger = logger
    @registry = nil
  end
  def warn_duplicate_bundle bundle, extras
    loaded = nil
    if bundle.is_a?(String)
      extras = extras.dup
      loaded = extras.shift()
    else
      loaded = bundle.inspect
      extras = extras.map(&:inspect)
    end
    @logger.warn "Duplicate bundles for id #{bundle.is_a?(String) ? bundle : bundle.id}", 'loaded' => loaded, 'ignored' => extras
  end
  def load_bundle_localised_resources bundle
    language_rx = /.*?\/([^\/]+)\.lproj\/([^\/]+)$/i
    res_paths = bundle.bundle_resources("")
    if res_paths.empty?
      @logger.debug "Bundle has no resource paths"
      return
    end
    loaded = {}
    loader = FileLoader.new(res_paths, @readers)
    BUNDLE_RESOURCES_TO_MERGE.each do |resource|
      loader.each_existing_readable("{,*.lproj/,../}#{resource}", :plist) do |path, content|
        lang = nil
        res_name = resource
        lang, res_name = $1, $2 if path.to_s =~ language_rx
        (loaded[resource] ||= {})[lang || ""] = path.to_s
        bundle.merge!({:res => {res_name => {lang => content}}})
      end
    end
    @logger.debug "Loaded bundle resources", loaded unless loaded.empty?
  end
  def load_bundle bundle_path
    result = nil
    @logger.info "Reading bundle #{bundle_path.to_s}" do
      App.call_extension_point :bundle_will_load, bundle_path
      result = super
      if result
        @logger.debug "Loaded #{result.id} main Info.plist"
        load_bundle_localised_resources result
        App.call_extension_point :bundle_did_load, result
      end
    end
    result
  end
  def load_qs_bundle path
    if path
      path = Pathname.new(path)
      load_bundle(path)
    else
      find_bundle_by_id(QS::BUNDLE_ID)
    end
  end
  def load_plugins list
    return find_bundles('*', false) if list == ['*']
    list.map { |name| find_bundles(name + '{,.qsplugin}').first }
  end
end
