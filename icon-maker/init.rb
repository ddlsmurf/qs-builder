$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '.')))

require 'shellwords'
require "media_wiki"
class MediaContext < RenderContext
  def path *segments
    segments.map { |e| MediaWiki::wiki_to_uri(e.to_s.gsub("*", "_STAR_").gsub(/[^a-z0-9_.-]/i, "_")) }.join "/"
  end
end
App.register do
  RESOURCE_IMAGE_EXTENSIONS = ["icns", "png", "tiff"]
  IMAGE_FORMATS = {
    :tiny => 18,
    :icon => 32,
    :large => 128
  }
  def convert_image input, output, resize = nil
    output = File.expand_path(output)
    res = `sips #{resize ? "-Z #{resize} " : ""}-s format png #{Shellwords.shellescape(input.to_s)} --out #{Shellwords.shellescape(output.to_s)} 2>&1 >/dev/null`
    unless $?.exitstatus.zero?
      @logger.warn "sips failed to convert #{input}", res
    else
      @logger.info "sips warnings for #{input}", res if res.length > 0
    end
    output
  end
  def get_icon_path bundle, iconpath
    @root_context.path(bundle.is_a?(QS::Plugin) ? "Plugin" : "Bundle", bundle ? bundle.id : "external", iconpath.basename.to_s.gsub(/\..[^.]+/, "")).gsub("/", "-")
  end
  def create_icons_for bundle, input_filename
    @logger.info "Converting #{input_filename}" do
      IMAGE_FORMATS.each_pair do |name, size|
        output = get_icon_path(bundle, input_filename) + "-#{name}.png"
        @writer.create_output_file(output) do |output_filename|
          convert_image input_filename, output_filename, size
        end
      end
    end
  end
  def get_icon_of_bundle name, bundle
    loaded = @plugin_by_id[bundle]
    loaded_bundle = nil
    if loaded
      loaded_bundle = loaded.info
      name ||= name.icon || loaded.info.icon_name
    else
      return nil if is_path?(bundle) # then it cant be a bundle id
      loaded_bundle = loaded = QS::Registry.get_app(bundle)
      name ||= loaded.icon_name
    end
    results = []
    if is_path?(name)
      results = Pathname.glob(loaded_bundle.path + name)
    else
      results = loaded_bundle.bundle_resources(name, *RESOURCE_IMAGE_EXTENSIONS)
    end
    if results.empty?
      #puts " -- nothing found for #{bundle}/#{name} (#{loaded_bundle.inspect})"
      nil
    else
      [loaded, results.first]
    end
  end
  def is_path? s
    s.is_a?(String) && (s.index("/") || s.start_with?("~"))
  end
  def get_icon_by_name name, owner_bundle
    return get_icon_by_name("ScriptIcon", owner_bundle) if name == {"type"=>"'osas'"} # So sue me!
    if name.is_a?(String) && is_path?(name)
      if File.exist?(name)
        return [nil, name]
      else
        @logger.warn "Icon at path: #{name} doesn't exist"
      end
    end
    result = nil
    resource = name.is_a?(Hash) ? name : @resource_by_id[name]
    if resource
      @logger.debug " Icon #{name.inspect} is a resource", *(resource.respond_to?(:info) ? [resource.inspect, resource.info.inspect] : [resource])
      if resource["bundle"]
        result = get_icon_of_bundle(resource["resource"] || resource["path"], resource["bundle"])
      else
        raise "Unknown resource format #{resource.info.inspect}" unless resource[:files]
        result = resource[:files].map do |entry|
          icon_by_name entry, resource.respond_to?(:plugin) ? resource.plugin : owner_bundle
        end.select { |e| e }
        result = result.empty? ? nil : result.first
      end
    end
    return result if result
    from_bundle = (owner_bundle.is_a?(QS::Plugin) ? owner_bundle.info : owner_bundle).bundle_resources(name, *RESOURCE_IMAGE_EXTENSIONS)
    return [owner_bundle, from_bundle.first] unless from_bundle.empty?
    qs_res = @template_data[:qs].bundle_resources(name, *RESOURCE_IMAGE_EXTENSIONS)
    return [@template_data[:qs], qs_res.first] unless qs_res.empty?
    name_is_a_bundle_result = get_icon_of_bundle(nil, name) if name.is_a?(String)
    return name_is_a_bundle_result if name_is_a_bundle_result
    nil
  end
  def icon_by_name name, owner_bundle
    res = (@icon_cache[owner_bundle] ||= {})[name]
    if res.nil?
      @logger.debug "Extracting icon #{name.inspect} requested in #{owner_bundle.inspect}" do
        res = get_icon_by_name name, owner_bundle
        if res
          @logger.info "Found icon in #{res[0] ? "(external path)" : res[0].inspect}: #{res[1]}"
        else
          @logger.info "No icon found for #{name} in #{owner_bundle.inspect}"
        end
      end
      @icon_cache[owner_bundle][name] = res ? res : false
    end
    res ? res : nil
  end
  def build_indexes data
    @plugin_by_id = {}
    data[:bundles].each { |b| @plugin_by_id[b.id.downcase] = b }
    objects_with_icons = {}
    @resource_by_id = {}
    QS::Registry.objects.each_pair do |name, val|
      if val.is_a?(QS::Resource)
        @resource_by_id[val.id] = val
      else
        icon = val['icon']
        objects_with_icons[val] = icon if icon && icon.length > 0
      end
    end
    QS::Registry.registration_kinds.each do |kind|
      QS::Registry.registrations(kind).each do |id, reg|
        icon = reg['icon']
        objects_with_icons[reg] = icon if icon && icon.length > 0
      end
    end
    objects_with_icons
  end
  def run_template data
    @template_data = data
    @root_context = MediaContext.new data, nil
    @logger = App.require_one :logger
    @writer = App.require_one :output_writer
    @icon_cache = {}
    generated_icons = {}
    objects_with_icons = build_indexes(data)
    unknowns = {}
    objects_per_icon_paths = {}
    icon_per_object = {}
    icons_loaded_per_bundle = {}
    @logger.info "Locating icons for #{objects_with_icons.length} QS objects" do
      objects_with_icons.each_pair do |object, icon|
        raise "not a string" unless icon.is_a?(String)
        @logger.debug "Locating icon #{icon} for #{object.inspect}" do
          container = object.plugin
          result = icon_by_name(icon, container)
          if result
            result[1] = Pathname.new(result[1])
            icon_per_object[object] = get_icon_path(result[0], result[1])
            (icons_loaded_per_bundle[result[0]] ||= []) << result[1]
            (objects_per_icon_paths[result[1].to_s] ||= []) << object
          else
            ((unknowns[icon] ||= {})[container.inspect] ||= []) << object
          end
        end
      end
    end
    @logger.info "Converting #{objects_per_icon_paths.count} (#{icon_per_object.count} objs) icons" do
      icons_loaded_per_bundle.each_pair do |bundle, list|
        list.uniq.each do |i|
          create_icons_for bundle, i
        end
      end
    end
    @writer.write_to_output "QSIcon.txt" do |f|
      f.puts "<noinclude>" + <<-DOC.gsub(/^        /, '')
        ==QSIcon template documentation==
        Includes a small icon for the Quicksilver object whose page is the first parameter,
        with the second parameter being an optional icon size: #{IMAGE_FORMATS.map { |k, s| "#{k} (for #{s} pixels)" }.join " or "}.
        
        ==Missing icons==
        Icons unable to find during generation of this template:
      DOC
      unknowns.each_pair do |icon, objects_per_plugin|
        f.puts "* Icon <nowiki>#{icon.inspect}</nowiki> not found, used by:"
        objects_per_plugin.each_pair do |plugin, objects|
          f.puts "** #{plugin}"
          objects.each { |o| f.puts "*** <nowiki>#{o.inspect}</nowiki>" }
        end
      end
      f.puts "</noinclude>{{#switch: \"{{{1}}}\"\n"
      icon_per_object.map { |k, v| " | \"#{@root_context.url_for(k)}\" = [[File:#{(@root_context.url() + v).gsub("/", "-")}-{{{2|icon}}}.png]]" }.each { |l| f.puts l }
      f.puts "}}"
    end
  end
end