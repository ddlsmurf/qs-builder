require 'lib/app'

module QS
  # Singleton class registering objects, providing lookups by id for Quicksilver plugins 
  # and bundles
  class Registry
    class << self
      # Empty all data
      def clear
        @@objects_by_id = {}
        @@objects_by_kind = {}
        @@externals = {}
        @@collisions = nil
      end
      # collisions[tablename][id]  is of collision
      def collisions
        @@collisions || {}
      end
      def log_collision id, table, *items
        list = (((@@collisions ||= {})[table] ||= {})[id] ||= [])
        @@collisions[table][id] = (list + items).uniq
      end
      # Add the object to the registry, and validate it.
      # 
      # If the object is a Registration it is added with its :kind as the table_name
      # otherwise it is added to the global id namespace
      def register object
        @@logger ||= App.require_one :logger
        object.validate if object.respond_to? :validate
        id = object.id
        raise "nil ID for #{object.inspect}" if id.nil?
        table = @@objects_by_id
        table_name = nil
        if object.is_a?(Registration)
          table_name = object[:kind]
          table = (@@objects_by_kind[table_name] ||= {})
        end
        previous = table[id]
        if previous
          log_collision id, table_name, object, previous
          @@logger.warn "Duplicate #{table_name || "objects"} with ID #{id.inspect}:", object.inspect, previous.inspect
        else
          table[id] = object
        end
      end
      # All the types of registrations known to the registry
      def registration_kinds
        @@objects_by_kind.keys
      end
      # Returns a Hash containing all the registrations of that kind
      def registrations kind
        @@objects_by_kind[kind] || {}
      end
      # Return an ObjectType for the specified type
      def get_type id
        @@externals[:types][id] ||= ObjectType.new({}, id, get_app)
      end
      # Return a Bundle for the specified id, or raises if not found
      def get_app id = QS::BUNDLE_ID
        @@externals[:apps][id] or raise "No app #{id} loaded !"
      end
      # Returns the global id hash
      def objects
        @@objects_by_id
      end
      # Loads all the plugins in the provided bundles, and returns an
      # array of results. Provide a block that loads and returns bundles.
      # 
      # [bundles] Array of Bundle
      # [qs_app] Bundle of Quicksilver.app
      def load_plugins bundles, qs_app, &bundle_loader # :yields: blundle_id_to_load
        raise "QSApp has wrong bundle id" unless qs_app.id == QS::BUNDLE_ID
        (@@externals[:apps] ||= {})[qs_app.id] = qs_app
        @@externals[:types] ||= {}
        result = bundles.map { |bundle| QS::Plugin.new bundle, qs_app }
        Registration.registrations_of(qs_app).each { |r| register r }
        result.map { |p| p.related_bundle_ids }.flatten.each do |id|
          (@@externals[:apps] ||= {})[id] = yield id
        end
        result
      end
      # Recursively register 
      def index *objects
        items = objects.flatten
        until items.empty?
          stack = []
          items.each do |o|
            register o
            stack += Array(o.objects_to_index) if o.respond_to? :objects_to_index
          end
          items = stack.flatten
        end
      end
    end
    clear
  end
end