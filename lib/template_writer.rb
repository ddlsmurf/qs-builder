require "lib/file_loader"
require "lib/file_writer"
require 'tilt'

module EnumExtension
  # Buffered enumeration providing fields such as is_last etc
  def self.enumerate_over enum # :yields: item, index, is_first, is_alternate, is_last
    first = true
    previous = nil
    have_previous = false
    i = 0
    enum.each do |element|
      if have_previous
        yield previous, i, first, (i % 2) == 1, false
        first = false
        i += 1
      end
      previous = element
      have_previous = true
    end
    if have_previous
      yield previous, i, first, (i % 2) == 1, true
      first = false
    end
    !first
  end
end

# Default class used as self when rendering templates
class RenderContext
  # Default object being rendered
  attr_accessor :this
  # Parent RenderContext or TemplateWriter if root
  attr_accessor :parent
  def initialize this, parent
    @this = this
    @parent = parent
  end
  def root?
    @parent.is_a?(TemplateWriter) || !@parent
  end
  def root
    cursor = self
    cursor = cursor.parent until cursor.root?
    cursor
  end
  # Returns the TemplateWriter
  def writer
    root.parent
  end
  # Create and return a new subcontext
  def sub_context_for new_this
    self.class.new new_this, self
  end
  # Renders the specified view and object and returns a string
  def render view_name, locals = {}, &block
    template = writer.load_template(view_name)
    template.render(self, locals.merge({:this => self.this}), &block)
  end
  # Enumerates over an enum running a partial for each entry
  # and adding the locals is_first, index, is_last, is_alt, list
  # 
  # Returns the result as string, or nil if no iterations were done
  def partial_enum view_name, enum, locals = {}, &block
    result = []
    did_any = EnumExtension.enumerate_over(enum) do |item, index, first, alt, last|
      result << partial(view_name, item, {:is_first => first, :index => index, :is_last => last, :is_alt => alt, :list => enum}.merge(locals), &block)
    end
    did_any ? result.join("") : nil
  end
  # Renders the specified object using a partial view name, returns
  # the result as a string
  def partial view_name, item, locals = {}, &block
    ctx = sub_context_for item
    view_name = "partials/_#{view_name}"
    ctx.render(view_name, item, locals, &block)
  end
end

class TemplateWriter
  def initialize logger, writer, template_paths, template_loaders
    @logger = logger
    @writer = writer
    @template_loader = FileLoader.new template_paths, template_loaders
  end
  def load_template view_name
    result = nil
    duplicates = []
    attempts = @template_loader.each_readable_with_basename(view_name) do |path, temp|
      if result
        duplicates << path
      else
        result = [path, temp]
      end
    end
    @logger.warn "Duplicate view for name #{view_name.inspect}", result[0], duplicates unless duplicates.empty?
    raise "View #{name} not found, searched: #{attempts.inspect}" unless result
    result[1]
  end
  def render_to output_name, view_name, this, context_klass = RenderContext, locals = {}, &block
    @writer.write_to_output output_name do |file|
      file.write(render(view_name, this, context_klass, locals, &block))
    end
  end
  def write_to_output *args, &blk
    @writer.write_to_output *args, &blk
  end
  def render view_name, this, context_klass = RenderContext, locals = {}, &block
    ctx = context_klass.new this, self
    ctx.render(view_name, locals, &block)
  end
end
