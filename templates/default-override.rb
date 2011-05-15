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
    include_key_in_plist = %w[CFBundleIdentifier QSModifiedDate CFBundleName QSPlugIn]
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
        current_version = (result[:versions] ||= {})[plugin['CFBundleVersion']] ||= { }
        reqs = plugin.requirements.map { |e| e.to_qsrequirement_entry }
        current_version['QSRequirements'] = reqs if reqs && !reqs.empty?
        current_version[:label] = plugin['CFBundleShortVersionString'] if plugin['CFBundleShortVersionString']
        qsapp_data = data[:qsapp][plugin.id]
        legacy = ""
        if qsapp_data && !qsapp_data.empty?
          qsapp_data = qsapp_data.dup
          legacy = qsapp_data.delete(:legacy) { "" }
          template = make_plugin_skeleton(plugin)
          qsapp_data[:template] = template unless template.empty?
          result['com.QSApp'] ||= qsapp_data
        end
        write_hash(plugin.id, result, legacy) if result
      end
    end
  end
end