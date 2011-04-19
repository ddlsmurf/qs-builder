
App.register do
  def run_template data
    INCLUDE_KEY_IN_PLIST = %w[CFBundleIdentifier QSModifiedDate CFBundleName CFBundleVersion QSPlugIn QSRequirements CFBundleShortVersionString]
    dicos = data[:bundles].map do |e|
      result = {}
      e.each_pair do |k,v|
        result[k] = v if INCLUDE_KEY_IN_PLIST.index(k)
      end
      result
    end
    # maybe add a filter for compatible QS version at this point ?
    dicos = { :plugins => dicos }
    dicos[:fullIndex] = true # Remove for incremental updates
    app.write_to_output(data[:config][:plist], dicos.to_plist)
  end
end