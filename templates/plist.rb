require "plist"
App.register do
  INCLUDE_KEY_IN_PLIST = %w[CFBundleIdentifier CFBundleName QSPlugIn QSRequirements QSPluginVersions]
  def build_latest_update_xml data
    data[:bundles].map do |plugin|
      result = {}
      INCLUDE_KEY_IN_PLIST.each do |key|
        value = plugin[key]
        result[key] = value if value
      end
      result
    end.sort { |a, b| a['CFBundleIdentifier'] <=> b['CFBundleIdentifier'] }
  end
  def run_template data
    @logger = App.require_one :logger
    @logger.info "Writing update plist files" do
      dicos = build_latest_update_xml(data)
      dicos = { :plugins => dicos }
      dicos[:fullIndex] = true # Remove for incremental updates
      App.require_one(:output_writer).write_to_output(data[:config][:plist]) do |f|
        f.write(dicos.to_plist)
      end
    end
  end
end