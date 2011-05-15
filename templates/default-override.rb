App.register do
  def write_hash name, *items
    @writer.write_to_output(name + ".yaml") do |f|
      items.each do |e|
        f.write(e.is_a?(String) ? e : e.to_yaml) if e
      end
    end
  end
  def copy_presets_recursively presets
    result = []
    presets.each do |p|
      copy = {'ID' => p.id}
      result << copy
      children = p.catalog_presets
      copy['children'] = copy_presets_recursively(children) if children && !children.empty?
    end
    result
  end
  def make_plugin_skeleton plugin
    result = {}
    unless plugin.actions.empty?
      actions = result['QSActions'] = {}
      plugin.actions.each { |a| actions[a.id] = nil }
    end
    unless plugin.catalog_presets.empty?
      result['QSPresetAdditions'] = copy_presets_recursively(plugin.catalog_presets)
    end
    result
  end
  def run_template data
    include_key_in_plist = %w[CFBundleIdentifier QSModifiedDate CFBundleName CFBundleVersion QSPlugIn QSRequirements CFBundleShortVersionString]
    @logger = App.require_one :logger
    @writer = App.require_one :output_writer
    @logger.info "Writing default overrides" do
      # pp data
      # data[:qsapp].each_pair { |id, val| write_hash(id.to_s, val) }
      data[:bundles].each do |plugin|
        result = {}
        include_key_in_plist.each do |key|
          value = plugin[key]
          result[key] = value if value
        end
        write_hash(plugin.id, result, data[:qsapp][plugin.id], make_plugin_skeleton(plugin)) if result
      end
    end
  end
end