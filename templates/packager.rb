$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '.')))

require 'shellwords'

App.register do
  def run_template data
    @logger = App.require_one :logger
    @logger.info "Building qspkg files" do
      dicos = data[:bundles].map do |e|
        @writer = App.require_one :output_writer
        @writer.create_output_file("#{e.id}.#{e["CFBundleVersion"]}.qspkg") do |output_filename|
          res = `/usr/bin/ditto -z --keepParent -rsrc -c #{Shellwords.shellescape(e.info.path.to_s)} #{Shellwords.shellescape(output_filename.to_s)} 2>&1`
          @logger.warn "Ditto output (#{$?.exitstatus})", res unless res.length == 0 && $?.exitstatus.zero?
        end
      end
    end
  end
end