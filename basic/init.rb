$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '.')))

require 'helpers/media_wiki_helpers'

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
class TemplateConfig
  def initialize data
    @data = data
  end
  def config ; @data[:config] || {} ; end
  def make_path *segments
    segments.map { |e| MediaWiki::wiki_to_uri(e.to_s.gsub("*", "_STAR_").gsub(/[^a-z0-9_-]/i, "_")) }.join "/"
  end
  def url *segments
    path = make_path *segments
    if config[:wiki_prefix]
      path = config[:wiki_prefix] + path
    else
      path
    end
  end
  def get_qs_segments obj, type
    values = []
    unless obj.is_a?(QS::Plugin) || obj.is_a?(Bundle)
      values += get_qs_segments(obj.plugin, nil)
    end
    values << obj.class.name.gsub("QS::", "")
    if type.nil? && (obj.is_a?(QS::Plugin) || obj.is_a?(Bundle))
      values << obj.name
    else
      values << obj.id
    end
    values << type if type
    values
  end
  def path_for obj, type = nil
    make_path(*get_qs_segments(obj, type))
  end
  def url_for obj, type = nil
    url(*get_qs_segments(obj, type))
  end
  def self.setup *args
    @@shared = TemplateConfig.new *args
  end
  def self.shared
    @@shared
  end
end
class MediaContext < RenderContext
  include Helpers
  include MediaWikiHelpers
  def config ; TemplateConfig.shared ; end
  def url_for obj, type = nil
    config.url_for obj, type
  end
end

App.register do
  def run_erb_template view_name, this, output_name, locals = {}, &block
    @writer.render_to output_name, "#{view_name}.erb", this, MediaContext, locals, &block
  end
  def run_template data
    config = TemplateConfig.setup data
    @logger = App.require_one :logger
    @writer = App.require_one :template_writer, Pathname.new(__FILE__).dirname + "views"
    plugins = {}
    plugins_by_app = {}
    data[:bundles].each do |bundle|
      plugins[bundle.id] = bundle
      run_erb_template "redirect", bundle, config.make_path("Plugin", bundle.name) + ".txt", :destination => "home"
      %w[tech preferences commands home].each do |sub_page|
        run_erb_template "plugin/#{sub_page}", bundle, config.path_for(bundle, sub_page) + ".txt"
      end
      bundle.related_bundle_ids.each { |id| (plugins_by_app[id] ||= []) << bundle }
    end
    plugins_by_app.each_pair do |app_id, plugins_of_app|
      app = QS::Registry.get_app app_id
      run_erb_template "redirect", app, config.make_path("Bundle", app.name) + ".txt", :destination => "home"
      run_erb_template "Bundle/home", app, config.path_for(app, "home") + ".txt", :plugins => plugins_of_app
    end
    run_erb_template "ListOfKeys", data, "ListOfKeys.htm"
    run_erb_template "ListOfWarnings", data, "ListOfWarnings.txt"
    run_erb_template "ListOfApplications", data, "ListOfApplications.txt"
    run_erb_template "ListOfRegistrations", data, "ListOfRegistrations.txt"
    run_erb_template "ListOfMediators", data, "ListOfMediators.txt"
    run_erb_template "ListOfPlugins", plugins, "ListOfPlugins.txt"
    if data[:config][:wiki_prefix]
      @logger.info "Dont forget to use the prefix #{data[:config][:wiki_prefix].inspect} when uploading!"
    else
      @logger.warn "Warning, using the wiki's global namespace, consider using --wiki-prefix Prefix/Name"
    end
  end
end