
require 'lib/hash_extensions'
require 'lib/app'
require 'lib/cli_logger'
require 'optparse'
require 'pathname'
require 'yaml'

class ConfigBuilder
  def initialize opts = {}
    @opts = opts
    @group_stack = []
  end
  def on *args, &block
    (@opts[@group_stack.last || ""] ||= []) << [args, block]
  end
  def add_to_option_parser parser, default_group_name = "General Options"
    keys = @opts.keys.sort
    keys << keys.shift() if keys.first == ""
    keys.each do |k|
      label = k || default_group_name
      opts.separator ""
      opts.separator "#{label}:" if label
      @opts[k].each { |o| parser.send(:on, *o[0], &o[1]) }
    end
  end
  def group name, &block
    @group_stack.push name
    yield
    @group_stack.pop
  end
end

App.register do
  @@config_merge_policy = HashExtensions.make_deep_merge_policy(:id)
  App.extension_point :config, :mediator => lambda { |a, b| a.merge!(b, &@@config_merge_policy) }
  App.extension_point :parse_options
  App.extension_point :validate_options
  App.extension_point :startup
  App.extension_point :run
  def logger
    @logger ||= CliLogger.new
  end
  def config
    @config ||= {}
  end
  def extension_did_load path
    logger.info "Loaded extension", :path => path.to_s
  end
  def build_config opts
    config = ConfigBuilder.new
    App.call_extension_point :make_config, config
    config.to_option_parser opts
  end
  def parse_options opts, global_config
    opts.on_tail("General options")

    opts.on_tail("-m", "--module PATH", "Load specified module (in PATH/init.rb). NB: modules may add parameters not otherwise visible in --help.") do |v|
      unless App.load_extensions v
        raise ArgumentError, "Could not find module #{v.inspect}"
      end
    end
    opts.on_tail("-v", "--[no-]verbose", "Run verbosely") do |v|
      logger.minimum = v ? :info : :warn
      @config[:verbose] = v
    end
    opts.on_tail("-d", "--[no-]debug", "Output debug information") do |v|
      logger.minimum = :debug if v
      @config[:debug] = v
    end
  end
  def main
    show_help = false
    @config ||= {}
    args = OptionParser.new
    App.call_extension_point :parse_options, args, @config
    args.on_tail("-h", "--help", "Show this help message") do
      show_help = true
    end
    begin
      args.parse!
      App.call_extension_point :validate_options, ARGV, @config
    rescue Exception => e
      logger.error("Problem parsing command line arguments: #{e}") unless e.is_a?(SystemExit)
      $stderr.puts(args)
      exit 1
    end
    if show_help
      $stderr.puts(args)
      exit 1
    end
    merged_config = App.require_one :config
    App.call_extension_point :startup, ARGV, merged_config
    App.call_extension_point :run, ARGV, merged_config
  end
end
