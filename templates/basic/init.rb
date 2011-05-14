require "media_wiki"
require 'helpers/media_wiki_helpers'
require "helpers/media_wiki_table_helpers"

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
    @logger.info "Writing Wiki pages" do
      plugins = {}
      plugins_by_app = {}
      data[:bundles].each do |bundle|
        plugins[bundle.id.downcase] = bundle
        run_erb_template "redirect", bundle, @root_context.path("Plugin", bundle.name) + ".txt", :destination => "home"
        %w[tech preferences commands home sidebar].each do |sub_page|
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
      run_erb_template "PluginSidebar", plugins, "PluginSidebar.txt"
      if data[:config][:wiki_prefix]
        @logger.info "Dont forget to use the prefix #{data[:config][:wiki_prefix].inspect} when uploading!"
      else
        @logger.warn "Warning, using the wiki's global namespace, consider using --wiki-prefix Prefix/Name"
      end
    end
  end
end