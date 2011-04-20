module QS
  # Prefix for keys used by overrides for the documentation system only
  CUSTOM_KEYS_PREFIX = "brdoc_"
  # Base abstract class for the tree of objects representing Quicksilvers plugin
  # plist data and the overrides
  class QSObject
    attr_reader :info, :parent
    # [info] Hash providing data about the object with it [] method
    # [id] String (or nil to figure it out automatically)
    # [parent] QSObject or Bundle that contains this object (I stuffed the globals under quicksilver.app's bundle)
    def initialize info, id, parent
      @info = info
      @id = id
      @parent = parent
    end
    def [] index
      pp self.class.name if info.is_a?(Array)
      info[index]
    end
    # Root QSObject (The one who's parent is – usually – a Bundle)
    def plugin
      @parent && @parent.respond_to?(:plugin) ? @parent.plugin : @parent || self
    end
    def id
      @id || self['ID'] || self['name'] || "'''No ID #{self.class}'''"
    end
    def keys
      info.keys
    end
    def name
      self['name'] || self.id
    end
    def description
      self['description']
    end
    def qs_get_all key, klass, parent = self, expected_klass = nil
      return enum_for(:qs_get_all, key, klass, parent, expected_klass) unless block_given?
      if parent.is_a?(String)
        container, parent = self[parent], self
      else
        container, parent = parent, parent
      end
      return [] unless container
      values = container[key]
      return [] unless values
      raise "Error getting #{key}: Got #{values.class} but expected #{expected_klass} in #{self.inspect}" unless expected_klass.nil? || values.is_a?(expected_klass)
      if values.is_a?(Array)
        values.each { |e| yield klass.new(e, nil, parent) }
      elsif values.is_a?(Hash)
        values.each_pair { |key, value| yield klass.new(value, key, parent) }
      else
        yield klass.new(values, nil, parent)
      end
    end
    protected :qs_get_all
    # Search for a key in the bundles resource table
    def localised_string table, key
      plugin.localised_string(table, key)
    end
    def inspect
      owner = nil
      owner = @parent ? plugin : nil
      owner = " of #{owner.name}" if owner.is_a?(Plugin)
      owner = " of #{owner.id == QS::BUNDLE_ID ? "Quicksilver internal" : plugin.id}" if owner.is_a?(Bundle)
      name = ": #{self.name}" if self.name
      "#<#{self.class.name}:#{id}#{owner}#{name}>"
    end
  end
  # Represents a requirement of a plugin
  # [type] can be any of REQUIREMENT_TYPES
  #   for type :path the key :path is a string, same for :version
  #   for type :feature the key :feature is a number
  class Requirement < QSObject
    REQUIREMENT_TYPES = [:bundle, :framework, :path, :qs_version, :feature, :plugin ]
    attr_accessor :type, :value
    def initialize type, info, parent
      super info, nil, parent
      @type = type
    end
    def self.requirements_of plugin
      result = []
      reqs = plugin['QSRequirements']
      plugin.report_error "Expected a dict at 'QSRequirements' (got a #{reqs.class.name})" if reqs && !reqs.is_a?(Hash)
      return [] unless reqs.is_a?(Hash)
      reqs.each_pair do |name, val|
        case name
        when "bundles" # Seems ignored – see QSPlugIn.m l: 512
          if val.is_a?(Array) && val.all? { |e| e.is_a?(Hash) }
            val.each do |e|
              plugin.check_keys(e, "QSRequirements/#{name}", %w[id name])
              result << Requirement.new(:bundle, e, plugin)
            end
          else
            plugin.report_error "Expected an array of dict at #{"QSRequirements/#{name}".inspect}"
          end
        when "frameworks"
          if val.is_a?(Array) && val.all? { |e| e.is_a?(Hash) }
            val.each do |fw|
              plugin.check_keys(fw, "QSRequirements/#{name}", %w[id name], ["resource"])
              result << Requirement.new(:framework, fw, plugin)
            end
          else
            plugin.report_error "Expected an array of dict at #{"QSRequirements/#{name}".inspect}"
          end
        when "paths"
          if val.is_a?(Array) && val.all? { |e| e.is_a?(String) }
            result += val.map { |p| Requirement.new(:path, {:path => p}, plugin) }
          else
            plugin.report_error "Expected an array of strings at #{"QSRequirements/#{name}".inspect}"
          end
        when "version"
          if val.is_a?(String)
            result << Requirement.new(:qs_version, {:version => val}, plugin)
          else
            plugin.report_error "Expected a string at #{"QSRequirements/#{name}".inspect}"
          end
        when "feature"
          if val.is_a?(Fixnum)
            result << Requirement.new(:feature, {:feature => val}, plugin)
          else
            plugin.report_error "Expected a number at #{"QSRequirements/#{name}".inspect}"
          end
        when "plugins"
          if val.is_a?(Array) && val.all? { |e| e.is_a?(Hash) }
            val.each do |p|
              plugin.check_keys(p, "QSRequirements/#{name}", [], %w[id name])
              result << Requirement.new(:plugin, p, plugin)
            end
          else
            plugin.report_error "Expected an array of dict at #{"QSRequirements/#{name}".inspect}"
          end
        else
          plugin.report_error "Has unused key #{"QSRequirements/#{name}".inspect}"
        end
      end
      result
    end
    def describe
      case type
      when :bundle
        "Application with id or name. Ignored if default QSIgnorePlugInBundleRequirements is true. Ignored anyway (see QSPlugIn.m:512)"
      when :framework
        "Framework '#{id}' in #{self['resource']}"
      when :path
        "Path at #{self[:path].inspect} must exist"
      when :qs_version
        "Quicksilver build later than #{self[:version]}"
      when :feature
        "Quicksilver feature level greater than #{self[:feature]}"
      when :plugin
        "Quicksilver plugin #{name.inspect}"
      else
        "Unknown: #{info.inspect}"
      end
    end
  end
  # Represents an entry of QSAction
  class Action < QSObject
    # Keys that I'm not sure QS uses
    UNCHECKED_KEYS = %w[rankModification directFileTypes description]
    # Keys I've confirmed QS uses
    KNOWN_KEYS = %w[actionClass actionProvider actionSelector actionSendToClass alternateAction 
      actionScript actionHandler actionEventClass actionEventID argumentCount icon name userData 
      directTypes indirectTypes resultTypes runInMainThread displaysResult indirectOptional reverseArguments 
      splitPlural validatesObjects initialize enabled precedence feature commandFormat]
    EXTRA_KEYS = ["#{CUSTOM_KEYS_PREFIX}notes"]
    def name
      localised_string("QSAction.name", id) || super
    end
    def description
      localised_string("QSAction.description", id) || super
    end
    # Returns a list of accepted direct types as QS::ObjectType instances
    def direct_types
      (self["directTypes"] || ['*']).map { |t| Registry.get_type(t) }
    end
    def indirect_types
      (self["indirectTypes"] || []).map { |t| Registry.get_type(t) }
    end
    # Array of Requirement instances
    def requirements
      unless @reqs
        @reqs = []
        @reqs << Requirement.new(:feature, {:feature => self['feature']}, plugin) if self['feature']
      end
      @reqs
    end
    # Array of strings with notes. Includes some custom data and the contents of the "#{CUSTOM_KEYS_PREFIX}notes" key if present.
    def notes
      res = []
      res += Array(self["#{CUSTOM_KEYS_PREFIX}notes"]) if self["#{CUSTOM_KEYS_PREFIX}notes"]
      res << "Re-opens Quicksilver with the results" if self['displaysResult']
      alternate_action = self['alternateAction']
      alternate_action = plugin.actions.select { |a| a.id == alternate_action}.first if alternate_action
      res << "Hold  ⌘ to run ''#{alternate_action.name}'' instead" if alternate_action
      res << "Implemented in AppleScript" if self['actionClass'] == "QSAppleScriptActions"
      res.select{|e|e}
    end
    # Check the QSAction for unexpected Keys and report to the plugin
    def validate
      plugin.check_keys info, "QSActions/#{id}", UNCHECKED_KEYS + KNOWN_KEYS + EXTRA_KEYS
    end
  end
  # Represents an entry under QSRegistration.
  # The key :kind contains the string name of the registration parent (so 'QSCommands' or the like)
  class Registration < QSObject
    def initialize kind, info, id, parent
      super info.is_a?(Hash) ? info : {:value => info}, id, parent
      @kind = kind
    end
    def [](index)
      index == :kind ? @kind : super
    end
    # Sub-class to use for specific registration kinds. All others use the base class QS::Registration
    def self.registration_types
      {
        'QSCommands' => Command,
        'QSProxies' => Proxy,
        'QSInternalObjects' => InternalObject,
        'QSPreferencePanes' => PreferencePane,
        'QSCommandInterfaceControllers' => UIController,
        'QSBundleChildHandlers' => BundleChildHandler,
        'QSBundleChildPresets' => BundleChildHandler
      }
    end
    # Read the registrations from the specified plugin, or from 
    # the bundle's localization table 'QSRegistration.plist'
    def self.registrations_of obj
      results = []
      parent = obj
      plugin = nil
      if obj.is_a?(Bundle)
        obj = obj.localisation_table('QSRegistration.plist')
      elsif obj.is_a?(Plugin)
        plist, obj = obj, obj['QSRegistration']
      else
        raise "Unexpected argument type for obj: (Wanted a Bundle or QS::Plugin) #{obj.inspect}"
      end
      plugin.report_error "No QSRegistration ?" if (!obj || obj.empty?) && plugin
      return results unless obj
      obj.each_pair do |kind, entries|
        unless entries.is_a? Hash
          plugin.report_error "Expected dict at QSRegistration/#{kind}" unless entries.is_a?(Hash)
          next
        end
        klass = registration_types[kind] || Registration
        plugin.report_error "Empty declaration QSRegistration/#{kind}" if plugin && entries.empty?
        entries.each_pair do |id, entry|
          results << klass.new(kind, entry, id, parent)
        end
      end
      results
    end
  end
  # Represents an object type in Quicksilver.
  # Retreive instances from the Registry only, an instance should
  # be unique per object type id.
  class ObjectType < QSObject
    # Find a registration for this object type
    def definition
      if @definition.nil?
        @definition = false
        reg = Registry.registrations("QSTypeDefinitions")[id]
        @definition = reg if reg
      end
      @definition || nil
    end
    # True if this ObjectType is NSFilenamesPboardType
    def files?
      id == "NSFilenamesPboardType"
    end
    def name
      if @name.nil?
        @name = false
        reg = definition
        @name = reg.name if reg
      end
      @name || localised_string("QSKindDescriptions.plist", id) || super
    end
  end
  # Registration with only a string value (usually a cocoa class name)
  # Read the :class key
  class ClassRegistration < Registration
    def info
      { :class => @info }
    end
  end
  # QSRegistration/QSCommands
  class Command < Registration ; end
  # QSRegistration/QSPreferencePanes
  class PreferencePane < Registration ; end
  # QSRegistration/QSCommandInterfaceControllers
  class UIController < ClassRegistration ; end
  # QSRegistration/QSProxies
  class Proxy < Registration
    # Array of ObjectType this proxy can represent
    def types
      (self["types"] || ['*']).map { |t| Registry.get_type(t) }
    end
  end
  # QSRegistration/QSInternalObjects
  class InternalObject < Registration ; end
  # QSRegistration/QSBundleChildPresets or QSRegistration/QSBundleChildHandlers
  class BundleChildHandler < ClassRegistration
    # Get the Bundle representing the application this handler handles
    def app
      Registry.get_app(id)
    end
  end
  # QSPresetAdditions entry
  class CatalogPreset < QSObject
    def name
      localised_string("QSCatalogPreset.name", id) || super
    end
    # true if the source is a QSGroupObjectSource
    def group?
      self['source'] == 'QSGroupObjectSource'
    end
    def requirements
      return @requirements if @requirements
      @requirements = []
      @requirements << Requirement.new(:bundle, { 'id' => self['requiresBundle'] }, self) if self['requiresBundle']
      @requirements << Requirement.new(:path, { :path => self['path'] }, self) if self['requiresPath']
      @requirements << Requirement.new(:path, { :path => self['settings']['path'] }, self) if self['requiresSettingsPath']
    end
    # Array of child entries (I think only if it's a group?)
    def catalog_presets
      @children ||= Array(qs_get_all('children', CatalogPreset, self, Array))
    end
    alias_method :objects_to_index, :catalog_presets
  end
  # QSTriggerAdditions entry
  class Trigger < QSObject ; end
  # Normalized QSResourceAdditions
  class Resource < QSObject
    def initialize info, id, parent
      if info.is_a?(Array)
        info = {:files => info}
      elsif info.is_a?(String)
        if info =~ /^\[([^\]]+)\]:(.+)$/
          info = {"bundle" => $1, "resource" => $2}
        else
          info = { :files => [info] }
        end
      end  
      super info, id, parent
    end
  end
  # Root QSObject for a plugin, reads
  # the root of the plist falling back on its QSPlugin key if the key isn't found.
  # 
  # @info is the Bundle containing the plugin, parent is nil
  class Plugin < QSObject
    # Array of warnings or nil
    attr_reader :misbehaviours
    # [bundle] Bundle containing the plugin
    # [qs] Bundle of quicksilver.app. TODO: Remove
    def initialize bundle, qs
      super bundle, bundle.id, nil
      @qs = qs
      Registry.index self
      validate
    end
    # Validate the plugin object adding errors to misbehaviours
    def validate
      check_keys qs_plugin, "QSPlugIn", %w[author categories description extendedDescription helpPage hidden icon infoFile relatedBundles secret]
      %w[QSActionsTemplate QSDefaultsTemplate QSPresetAdditionsTemplate QSRegistrationTemplate QSRequirementsTemplate].each do |k|
        report_error "Unknown key: #{k.inspect}" if @info[k]
      end
      if reg = self['QSRegistration']
        %w[QSPreferencePanesTemplate].each do |k|
          report_error "Unknown key: QSRegistration/#{k.inspect}" if @info[k]
        end
      end
      if @info['QSRegistryTables']
        report_error "Check QSRegistryTables shouldn't be QSRegistration/QSRegistryHeaders instead"
      end
    end
    # A unique array of bundle IDs of related or required apps by this
    # plugin, any of its catalogs etc...
    def related_bundle_ids
      return @related_bundles if @related_bundles
      result = Array(self['relatedBundles'])
      each_catalog_preset do |preset, depth|
        reqs = preset.requirements
        next unless reqs
        result += Array(preset.requirements.select { |r| r.type == :bundle }.map { |r| r['id'] })
      end
      if requirements
        result += Array(requirements.select { |r| r.type == :bundle }.map { |r| r['id'] })
      end
      browsable_bundles.each { |bundle| result << bundle.id }
      @related_bundles = result.flatten.uniq
    end
    # Append the error to misbehaviours
    def report_error error
      (@misbehaviours ||= []) << error
    end
    # Check the object for unknown and required keyrs.
    # 
    # [object] object reponding to [] and each_key to check
    # [path] String to prefix to error reports (should represent the key path from the plugin to object)
    # [allowed] Array of keys to expect in object. (Automatically includes required)
    # [required] Array of keys to warn if absent in object
    def check_keys object, path, allowed = [], required = []
      allowed += required if allowed && required
      required.each { |k| report_error("Missing required key: #{"#{path ? path + "/" : ""}#{k}".inspect}") unless !object[k].nil? }
      object.each_key { |k| report_error("Unknown key: #{"#{path ? path + "/" : ""}#{k}".inspect}") unless allowed.index(k) }
    end
    def localised_string table, key
      @info.localised_string(table, key)
    end
    def [] index
      super || qs_plugin && qs_plugin[index]
    end
    def keys
      info.keys + qs_plugin.keys.map { |k| 'QSPlugIn/' + k } + (self['QSRegistration'] || {}).keys.map { |k| 'QSRegistration/' + k }
    end
    def id
      @info.id
    end
    def description
      qs_plugin && qs_plugin['description']
    end
    def name
      self['CFBundleName']
    end
    # shortcut to the 'QSPlugin' key
    def qs_plugin
      self['QSPlugIn']
    end
    # Recursively yield each catalog preset
    def each_catalog_preset list = self.catalog_presets, depth = 0, &blk # :yields: CatalogPreset, depth
      return enum_for(:each_catalog_preset, list, depth) unless blk
      list.each do |preset|
        yield preset, depth
        children = preset.catalog_presets
        each_catalog_preset(children, depth + 1, &blk) if children
      end
    end
    # Array of objects to register in the QS::Registry
    def objects_to_index
      #pp self['QSResourceAdditions']
      # pp self.requirements#
      [actions, catalog_presets, registrations, resources, triggers]
    end
    # Yield each object there is a class for in the QS namespace contained
    # in this plugin.
    def each &blk
      return enum_for(:each) unless blk
      each_catalog_preset.map{|l,d|l}.each(&blk)
      items = objects_to_index.flatten.select { |e| !e.is_a?(CatalogPreset) }
      until items.empty?
        stack = []
        items.each do |o|
          yield o
          stack += Array(o.objects_to_index) if o.respond_to? :objects_to_index
        end
        items = stack.flatten
      end
    end
    # List of the root Requirement s.
    # 
    # Actions and other sub-objects might contain additional requirements. Write a warning for that ?
    def requirements ; @requirements ||= Requirement.requirements_of self ; end
    def registrations ; @registrations ||= Registration.registrations_of self ; end
    def resources ; @resources ||= Array(qs_get_all('QSResourceAdditions', Resource, self, Hash)) ; end
    def triggers ; @triggers ||= Array(qs_get_all('QSTriggerAdditions', Trigger, self, Array)) ; end
    def actions ; @actions ||= Array(qs_get_all('QSActions', Action, self, Hash)) ; end
    def browsable_bundles ; registrations.select { |e| e.is_a?(BundleChildHandler) } ; end
    def commands ; registrations.select { |e| e.is_a?(Command) } ; end
    def proxies ; registrations.select { |e| e.is_a?(Proxy) } ; end
    def internal_objects ; registrations.select { |e| e.is_a?(InternalObject) } ; end
    def preference_panes ; registrations.select { |e| e.is_a?(PreferencePane) } ; end
    def ui_controllers ; registrations.select { |e| e.is_a?(UIController) } ; end
    # List of the root QSPresetAdditions
    def catalog_presets ; @catalog_presets ||= Array(qs_get_all('QSPresetAdditions', CatalogPreset, self, Array)) ; end
  end
end