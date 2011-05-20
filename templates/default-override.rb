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
    result = {
      'QSPlugin' => {
        'recommended' => plugin['recommended'] || false
      }
    }
    unless plugin.actions.empty?
      actions = result['QSActions'] = {}
      plugin.actions.each { |a| actions[a.id] = nil }
    end
    unless plugin.catalog_presets.empty?
      result['QSPresetAdditions'] = copy_presets_recursively(plugin.catalog_presets)
    end
    result
  end
  def self.add_key_or_alternative hash, key, value
    return unless value
    previous = hash[key]
    if previous
      (hash["#{key}_alt"] ||= []) << value
    else
      hash[key] = value
    end
  end
  def copy_legacy_version output, legacy_version, requirements = []
    self.class.add_key_or_alternative(output, 'QSModifiedDate', "#{legacy_version['modified']} -0800") if legacy_version['modified']
    self.class.add_key_or_alternative(output, 'CFBundleShortVersionString', legacy_version['version']) if legacy_version['version']
    max_version = legacy_version['maxversion']
    if max_version
      if max_version < 0xFFFFFFFF
        max_version = max_version.to_s(16).upcase if max_version.is_a?(Fixnum)
        requirements << QS::Requirement.version(nil, max_version, :qs_max).to_qsrequirement_entry
      end
    end
    min_version = legacy_version['minversion']
    if min_version
      if min_version > 0
        min_version = min_version.to_s(16).upcase if max_version.is_a?(Fixnum)
        requirements << QS::Requirement.version(nil, min_version, :qs_min).to_qsrequirement_entry
      end
    end
    self.class.add_key_or_alternative(output, 'QSRequirements', requirements) unless requirements.nil? || requirements.empty?
  end
  def add_plugin_version output, plugin, qs_app
    version_id = plugin['CFBundleVersion']
    if !version_id || version_id.strip.length == 0
      @logger.warn "Plugin has no CFBundleVersion key", plugin.inspect
      return
    end
    versions = (output['QSPluginVersions'] ||= {})
    current_version = (versions[version_id] ||= {})
    copy_legacy_version current_version, plugin, plugin.requirements.map { |r| r.to_qsrequirement_entry }
    if info = qs_app[:info]
      if info['version'] == version_id && info['updated']
        self.class.add_key_or_alternative(output, 'QSModifiedDate', "#{info['updated']} 00:00:00 +0000")
      end
    end
    legacy = qs_app[:legacy]
    copy_legacy_version(current_version, legacy) if legacy
    return unless legacy && legacy[:versions]
    legacy[:versions].
      select { |v| v['build'] && v['build'].strip.length > 0 && (v['maxversion'] || 0) > 0 }.
      each do |version|
        existing = (versions[version['build']] ||= {})
        next unless existing
        copy_legacy_version existing, version
    end
  end
  def build_plugin_override plugin, qs_app
    include_key_in_plist = %w[CFBundleIdentifier CFBundleName QSPlugIn]
    result = {}
    include_key_in_plist.each { |key| result[key] = plugin[key].dup if plugin[key] } if plugin
    add_plugin_version result, plugin, qs_app
    template = plugin ? make_plugin_skeleton(plugin) : []
    qsapp_data = (result['com.QSApp'] ||= {})
    qsapp_data['wiki'] = qs_app[:wiki] if qs_app[:wiki]
    qsapp_data['info'] = qs_app[:info] if qs_app[:info]
    qsapp_data['template'] = template unless template.empty?
    legacy = qs_app[:legacy]
    qsplugin = (result['QSPlugIn'] ||= {})
    copy_over = {
      ':author/author_name' => 'author',
      ':author/author_url' => 'author_url',
      'image' => 'webIcon',
      ':repository' => 'repository_url'
    }.each_pair do |source_path, dest_key|
      HashExtensions.find_path(source_path, qsapp_data, qs_app, legacy) do |v|
        self.class.add_key_or_alternative(qsplugin, dest_key, v)
      end
    end
    result
  end
  def run_template data
    @logger = App.require_one :logger
    @writer = App.require_one :output_writer
    @logger.info "Writing default overrides" do
      # pp data
      seen = {}
      # data[:qsapp].each_pair { |id, val| write_hash(id.to_s, val) }
      data[:bundles].each do |plugin|
        result = build_plugin_override plugin, (data[:qsapp] || {})[plugin.id] || {}
        seen[plugin.id] = true
        write_hash(plugin.id, result) if result
      end
      data[:qsapp].each_pair do |id, data|
        unless seen[id]
          write_hash("Unavailable/#{id}", data)
        end
      end
    end
  end
end