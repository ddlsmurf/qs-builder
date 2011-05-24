App.register do
  def run_template data
    include_key_in_plist = %w[CFBundleIdentifier CFBundleName QSPlugIn QSRequirements QSPluginVersions]
    @logger = App.require_one :logger
    @logger.info "Writing update plist files" do
      dicos = data[:bundles].map do |plugin|
        result = {}
        include_key_in_plist.each do |key|
          value = plugin[key]
          result[key] = value if value
        end
      end
      # maybe add a filter for compatible QS version at this point ?
      dicos = { :plugins => dicos }
      dicos[:fullIndex] = true # Remove for incremental updates
      App.require_one(:output_writer).write_to_output(data[:config][:plist]) do |f|
        f.write(dicos.to_plist)
      end
    end
  end
end