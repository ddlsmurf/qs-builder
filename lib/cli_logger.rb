require 'yaml'

class CliLogger
  class ReraisedSilentException < StandardError
    attr_accessor :original
    def initialize orig
      self.original = orig
    end
    def message ; @original.message ; end
  end
  LEVELS = %w[debug info warn error fatal].map(&:to_sym)
  @@longest_level_name = LEVELS.map{ |e| e.to_s.length }.max()
  attr_accessor :minimum, :prefix
  attr_accessor :minimum_when_failed
  def initialize minimum = :warn, prefix = nil
    @prefix = prefix && !prefix.empty? ? " #{prefix}:" : ""
    @indents = []
    self.minimum = minimum
    self.minimum_when_failed = :info
  end
  def minimum ; LEVELS[@minimum] ; end
  def minimum= value ; @minimum = LEVELS.index value ; end
  def minimum_when_failed ; LEVELS[@minimum_when_failed || @minimum] ; end
  def minimum_when_failed= value ; @minimum_when_failed = value.is_a?(Symbol) ? LEVELS.index(value) : value ; end
  def self.indent(s, first = 0, others = 0)
    "#{(" " * first)}#{s.gsub(/\n$/m, "").gsub("\n", "\n#{(" " * others)}")}"
  end
  def write message, level = :info, depth = 0, *arguments
    header = "#{level.to_s.rjust(@@longest_level_name)}:#{@prefix} "
    $stderr.puts "#{header}#{CliLogger.indent(message, depth * 2, header.length + depth * 2)}"
    unless arguments.empty?
      arguments = arguments.first if arguments.count == 1
      header_len = (depth + 1) * 2 + header.length
      $stderr.puts(CliLogger.indent(arguments.to_yaml.sub("--- \n", ""), header_len, header_len))
    end
    raise SystemExit if level == :fatal
  end
  protected :write
  def log message, level = :info, *arguments
    parent_indent = @indents.last
    if parent_indent
      parent_indent << [message, level, @indents.size, arguments]
    else
      return nil unless LEVELS.index(level) >= @minimum
      write message, level, 0, *arguments
    end
    nil
  end
  def indent message, level, *arguments
    #puts "Indenting at\n\t#{caller().join"\n\t"}"
    @indents << [[message, level, @indents.size, arguments]]
  end
  def unindent_at minimum_level = @minimum
    #puts "Unindenting at #{minimum_level}\n\t#{caller().join"\n\t"}"
    popped_indent = @indents.pop
    parent_indent = @indents.last
    minimum_level = LEVELS.index(minimum_level) if minimum_level.is_a?(Symbol)
    popped_indent.each do |message, level, depth, arguments|
      if LEVELS.index(level) >= minimum_level
        if parent_indent
          parent_indent << [message, level, depth, arguments]
        else
          write message, level, depth, *arguments
        end
      end
    end
    nil
  end
  def indented message, level = :info, *arguments, &block
    indent message, level, *arguments
    res = nil
    begin
      res = yield
    rescue ReraisedSilentException => r
      raise
    rescue Exception => e
      log_exception(nil, e)
      unindent_at(@minimum_when_failed || @minimum)
      raise ReraisedSilentException.new(e)
    end
    unindent_at(@minimum)
    res
  end
  CALLERS_TO_IGNORE = [ # :nodoc:
    /lib\/app|cli_(app|logger)\.rb$/,
  ]
  def log_exception message, ex, level = :error
    log(message || "Unexpected exception", level, ex, Array(ex.backtrace. # Thank you sinatra
      map    { |line| line.split(/:(?=\d|in )/) }.
      reject { |file,line,func| CALLERS_TO_IGNORE.any? { |pattern| file =~ pattern } }.
      map    { |*a| a.join(": ") }))
  end
  def method_missing(meth, *args, &blk)
    if LEVELS.index(meth)
      message = args.shift()
      if blk
        indented(message, meth, *args, &blk)
      else
        log(message, meth, *args)
      end
    else
      super
    end
  end
end
