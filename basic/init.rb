$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '.')))

require "media_wiki"
require 'helpers/media_wiki_helpers'
require "helpers/media_wiki_table_helpers"

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

class MediaContext < RenderContext
  include MediaWikiHelpers
  include MediaWikiTableHelpers
  def path *segments
    segments.map { |e| MediaWiki::wiki_to_uri(e.to_s.gsub("*", "_STAR_").gsub(/[^a-z0-9_.-]/i, "_")) }.join "/"
  end
end

App.register do
  def run_erb_template view_name, this, output_name, locals = {}, &block
    @writer.render_to output_name, "#{view_name}.erb", this, MediaContext, locals, &block
  end
  def run_template data
    @root_context = MediaContext.new data, nil
    @logger = App.require_one :logger
    @writer = App.require_one :template_writer, Pathname.new(__FILE__).dirname + "views"
    plugins = {}
    plugins_by_app = {}
    data[:bundles].each do |bundle|
      plugins[bundle.id.downcase] = bundle
      run_erb_template "redirect", bundle, @root_context.path("Plugin", bundle.name) + ".txt", :destination => "home"
      %w[tech preferences commands home].each do |sub_page|
        run_erb_template "plugin/#{sub_page}", bundle, @root_context.path_for(bundle, sub_page) + ".txt"
      end
      bundle.related_bundle_ids.each { |id| (plugins_by_app[id] ||= []) << bundle }
    end
    plugins_by_app.each_pair do |app_id, plugins_of_app|
      app = QS::Registry.get_app app_id
      run_erb_template "redirect", app, @root_context.path("Bundle", app.name) + ".txt", :destination => "home"
      run_erb_template "Bundle/home", app, @root_context.path_for(app, "home") + ".txt", :plugins => plugins_of_app
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