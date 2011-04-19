require 'lib/app'

module QS
  class Registry
    class << self
      def clear
        @@objects_by_id = {}
        @@objects_by_kind = {}
        @@externals = {}
        @@collisions = nil
      end
      def collisions
        @@collisions || []
      end
      def log_collision id, table, *items
        list = (((@@collisions ||= {})[table] ||= {})[id] ||= [])
        @@collisions[table][id] = (list + items).uniq
      end
      def register object
        @@logger ||= App.require_one :logger
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
      def registration_kinds
        @@objects_by_kind.keys
      end
      def registrations kind
        @@objects_by_kind[kind] || {}
      end
      def get_type id
        @@externals[:types][id] ||= ObjectType.new({}, id, get_app)
      end
      def get_app id = QS::BUNDLE_ID
        @@externals[:apps][id] or raise "No app #{id} loaded !"
      end
      def objects
        @@objects_by_id
      end
      def load_plugins bundles, qs_app, &bundle_loader
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