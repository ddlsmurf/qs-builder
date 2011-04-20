require 'pathname'
# Very 'fun to fiddle with but not much more' dependency injection
# 
# You get:
#   :extension points: Methods than can be called on any extension.
#      A point can store additional configuration, such as a mediator method
#      that is used to reduce the results of each extension's implementation.
#      Is created on demand, or defined with App.extension_point
#   :extensions: Instances that implement the code ran. They must be
#      registered with App.register.
# 
# On startup, runs the extension point :main
# 
#   Doesn't this look exactly as if some amateur was
#   strongly inspired by sinatra ?
class App
  class << self
    # Deletes all known extensions and extension points
    def clear_extensions
      @extensions = []
      @extension_points = {}
    end
    # Register an extension instance, or create one with an
    # anonymous class in which the block is evaluated, then
    # instantiate and register that
    def register *mods, &block
      if block_given?
        k = Class.new
        k.class_exec(&block)
        mods << k.new
      end
      if mods
        mods.each do |extension|
          @extension_points.each_pair { |name, val| (val[:handlers] ||= []) << extension if extension.respond_to?(name) }
        end
        @extensions += mods
      end
    end
    # Define or refine an extension point that may be implemented
    # 
    # options can include:
    #   :mediator: A lambda provided to Enumerable#reduce when require_one is called
    # 
    # Includes a :handlers key which contains an up to date list of extensions
    # implementing this list, don't mess with it.
    def extension_point name, options = {}
      name = name.to_sym
      point = @extension_points[name]
      if point
        unless options.empty?
          handlers = options.delete(:handlers)
          point[:handlers] = (handlers + point[:handlers]).uniq if handlers
          point.merge!(options)
        end
      else
        point = @extension_points[name] = { :handlers => Array(@extensions.select { |e| e.respond_to?(name) }) }.merge(options)
      end
      point
    end
    # yields each extension instance that responds_to name
    def extensions_for_point name, &block # :yields: extension
      return enum_for(:extensions_for_point, name) unless block_given?
      extension_point(name)[:handlers].each(&block)
    end
    # yields once each extension that responds_to name, allowing
    # for the code in the provided block to add new handlers on the
    # way
    #
    # Returns nothing
    def each_handler name, &block # :yields: extension
      return enum_for(:each_handler, name) unless block_given?
      point = extension_point(name)
      ext = point[:handlers]
      done = []
      while ext && !ext.empty?
        ext.each(&block)
        done += ext
        ext = point[:handlers] - done
      end
      nil
    end
    # Calls each extension's name method, with the provided
    # arguments and block.
    # 
    # Returns nothing
    def call_extension_point name, *arguments, &block
      each_handler name do |e|
        e.send(name, *arguments, &block)
      end
    end
    # Calls each extension's name method, with the provided
    # arguments.
    # 
    # Returns an array of the results, or if a block
    #   was given, returns whatever Enumerable#reducer
    #   with that block returns on the array of results.
    # 
    # All nil s returned are ignored
    def get_all name, *arguments, &reducer
      result = []
      each_handler(name) do |e|
        res = e.send(name, *arguments)
        result << res unless res.nil?
      end
      result = result.reduce(&reducer) if reducer
      result
    end
    # Uses the provided block or the extension_point's :mediator
    # to reduce the results of get_all to one single result.
    # 
    # If no reducer is available, uses the single result, and raises
    #   if there is more that one result.
    # Raises if no extension responds to name.
    def require_one name, *arguments, &reducer
      reducer = extension_point(name)[:mediator] if !reducer
      result = get_all(name, *arguments, &reducer)
      if !reducer
        raise RuntimeError, "Error: no extension provides #{name.inspect}" if result.empty?
        raise RuntimeError, "Error: more than one extension provides #{name.inspect}, but no reducer" if result.count > 1
        return result.first
      end
      raise RuntimeError, "Error: no extension provides #{name.inspect}" if result.nil? || result.empty?
      result
    end
    # Requires the file path/init.rb if it exists
    # 
    # Calling the extension points :extension_will_load and
    # :extension_did_load respectively before and after.
    def load_extensions path
      anything = false
      extension_path = (Pathname.new(path) + 'init.rb').expand_path
      if extension_path.file?
        call_extension_point :extension_will_load, extension_path
        if require extension_path.to_s.gsub(/.rb$/i, "")
          anything = true
          call_extension_point :extension_did_load, extension_path
        end
      end
      anything
    end
  end
  clear_extensions
  at_exit { App.call_extension_point :main unless $! }
end