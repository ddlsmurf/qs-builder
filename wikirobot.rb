#!/usr/bin/env ruby

begin
  %w[media_wiki pathname shellwords pp yaml digest].each { |e| require e }
rescue LoadError => e
  retry if require 'rubygems'
  raise
end

$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '.')))
require 'lib/folder_scanner'
require "media_wiki"
class BlankSlate
  instance_methods.each { |meth| undef_method(meth) unless meth =~ /\A__/ }
end
module MediaWiki
  class Gateway
    def create(title, content, options={})
      form_data = {'action' => 'edit', 'title' => title, 'text' => content, 'summary' => (options[:summary] || ""), 'token' => get_token('edit', title)}
      form_data['createonly'] = "" unless options[:overwrite]
      make_api_request(form_data)
    end
    def page_rev_ids(page_titles)
      server_info = {}
      page_titles.each_slice(50) do |titles|
        form_data = {'action' => 'query', 'prop' => 'info', 'titles' => titles.join("|")}
        pages = make_api_request(form_data)
        normalised_title_list = pages.first.elements["query/normalized"]
        normalized = {}
        if normalised_title_list
          norm = normalised_title_list.each do |n|
            normalized[n.attributes['to']] = n.attributes['from']
          end
        end
        pages.first.elements["query/pages"].each do |page|
          if valid_page? page
            title = page.attributes['title']
            title = normalized[title] if normalized.has_key? title
            server_info[title] = page.attributes['lastrevid'].to_i
          end
        end
      end
      server_info
    end
  end
end
class FakeGateway < BlankSlate
  def initialize host
    @host = host
    @delegate = MediaWiki::Gateway.new host
  end
  def method_missing(meth, *args, &block)
    res = nil
    read_only_methods = %w[login list page_rev_ids].map(&:to_sym)
    if read_only_methods.index(meth)
      return @delegate.send(meth, *args, &block)
    end
    case meth
    when :delete
      puts " (Skipping delete of #{args.inspect} because of dry-run)"
    when :edit
      puts " (Skipping upload of #{args[1].size} bytes to #{args[0].inspect}, options = #{args[2].inspect})"
      res = [""]
    else
      puts "!!! Unknown #{meth.inspect}"
    end
    res
  end
end
class App
  def parse_options
    @options = {
      :wiki_url => "https://192.168.0.125/api.php",
      :wiki_creds => ['guest', 'guest'],
      :wiki_prefix => "Auto/",
      :wiki_comment => 'Robot commit',
      :scanner => FolderScanner::Options.new
    }
    arguments = OptionParser.new do |opts|
      opts.banner = "Upload pages and files to a MediaWiki server\nUsage: wiki.rb [options] folders_to_upload\n.txt get their extension removed."

      opts.on("--wiki URL", "Path to wiki api.php") do |v|
        @options[:wiki_url] = v
      end
      opts.on("-c", "--credentials USER", "Username to access the wiki") do |v|
        res = v.split(":", 2)
        raise "Credentials must be in the format user:pass" unless res.count == 2
        raise "Credential username cannot be empty" unless !res[0].empty?
        @options[:wiki_creds] = res
      end
      opts.on("-k", "--use-keychain ITEM_NAME", "Load credentials from Mac OS X Keychain") do |v|
        @options[:keychain] = v
      end
      opts.on("-m", "--comment MSG", "Comment to use on wiki page updates") do |v|
        @options[:wiki_comment] = v.split(":")
      end
      opts.on("-p", "--prefix PREFIX", "Always add prefix to any Page name") do |v|
        @options[:wiki_prefix] = v
      end
      opts.on("-l", "--list [PREFIX]", "List pages matching PREFIX and exit") do |v|
        @options[:ls] = v || ""
      end
      opts.on("--track FILENAME", "Track edits using FILENAME. Using this means you get warnings if someone else edited a page you are uploading, and only upload changed files.") do |v|
        @options[:tracker] = v
      end
      opts.on("--force", "Track edits using FILENAME. Using this means you get warnings if someone else edited a page you overwrote.") do
        @options[:force] = true
      end
      opts.on("--delete-all PREFIX", "Delete all pages matching PREFIX and exit") do |v|
        @options[:delete_all] = v
      end
      opts.on("-D", "--dry-run", "Don't actually change anything on the server") do |v|
        @options[:dry_run] = true
      end
      @options[:scanner].parse(opts)
    end
    begin
      arguments.parse!
    rescue SystemExit => sex
      exit 1
    rescue Exception => e
      puts "Error: #{e}\n\n"
      puts arguments
      exit 1
    end
  end
  def get_page_name file
    file = file[0..-5] if file =~ /\.txt$/i
    @options[:wiki_prefix] + File.basename(file)
  end
  def get_keychain_account name
    keychain = {}
    `security find-internet-password -gl #{Shellwords.shellescape(@options[:keychain])} 2>&1`.
    scan(/^\s*(?:([^:]+): |"([a-z0-9 _]{4})"<[^>]*>=)"(.*)"$/i).each { |entry| keychain[entry[0] || entry[1]] = entry[2] if entry[2]}
    raise "Keychain item #{v.inspect} not found (or no account)" if !keychain["acct"] || keychain["acct"].empty?
    raise "Keychain item #{v.inspect} not found (or no password)" if !keychain["password"]
    $stderr.puts "Using account #{keychain["acct"].inspect} from keychain"
    [keychain["acct"], keychain["password"]]
  end
  def login
    return @wm if @wm
    @options[:wiki_creds] = get_keychain_account(@options[:keychain]) if @options[:keychain]
    mw = (@options[:dry_run] ? FakeGateway : MediaWiki::Gateway).new(@options[:wiki_url])
    mw.login(*@options[:wiki_creds])
    $stderr.puts "Logged on to #{@options[:wiki_url]} as #{@options[:wiki_creds][0]}" +
      (@options[:wiki_prefix] ? " (using prefix #{@options[:wiki_prefix].inspect})" : "")
    @wm = mw
  end
  def upload(file, name, as_page)
    cx = login
    $stderr.puts "Uploading #{name} from #{file}"
    result = nil
    if as_page
      File.open(file, "r") { |f| result = cx.edit(name, f.read(), :summary => @options[:wiki_comment]) }
    else
      result = cx.upload(file, :filename => name.gsub("/", "-"), :ignorewarnings => true, :comment => @options[:wiki_comment])
      result = nil
    end
    return [] unless result
    res = result[0].elements["edit"]
    if res.attributes['nochange']
      []
    else
      %w[oldrevid newrevid].map { |e| res.attributes[e].to_i }
    end
  end
  def file_to_wiki_info name, relative_path
    is_page = name =~ /\.txt$/i
    base_name = File.basename(name)
    base_name = base_name[0..-5] if is_page
    base_name = relative_path == "" ? base_name : File.join(relative_path, base_name)
    digest = Digest::SHA2.file(name).hexdigest
    { :server_name => @options[:wiki_prefix] + base_name,
      :page? => !!is_page,
      :from => name,
      :digest => digest }
  end
  def process_file file
    server_name = file[:server_name]
    (@tracker[server_name] ||= {}).merge!({:from => file[:from]})
    res = []
    unless !@options[:force] && @tracker[server_name][:digest] == file[:digest]
      res = upload(file[:from], server_name, file[:page?])
      if file[:page?]
        if res.empty?
          puts "  (no change)"
        else
          if @tracker[server_name][:prev]
            if @tracker[server_name][:prev] != res[0]
              puts "Warning: Overwrote externally edited page #{server_name}"
            end
          end
          @tracker[server_name][:prev] = res[1]
        end
      end
    end  
    @tracker[server_name][:digest] = file[:digest]
  end
  def run
    parse_options
    cx = login
    if ARGV.length > 0 && (@options[:ls] || @options[:delete_all])
      $stderr.puts "warning: Using the --list or --delete-all switches prevents uploading of #{ARGV.inspect}"
    end
    if @options[:ls]
      prefix = @options[:wiki_prefix] + @options[:ls]
      $stderr.puts "List matching #{prefix.inspect}"
      puts cx.list(prefix).to_yaml
      exit 0 unless @options[:delete_all]
    end
    if @options[:delete_all]
      prefix = @options[:wiki_prefix] + @options[:delete_all]
      list = cx.list(prefix)
      $stderr.puts "Deleting all pages matching #{prefix.inspect} (#{list.count} pages)"
      list.each do |p|
        cx.delete p
        $stderr.puts "  => #{p.inspect} deleted"
      end
      exit 0
    end
    #cx.get(["Auto/Plugin/Automator_Module", "Auto/Plugin/Apple_Mail_Module"].join "|")
    files = {}
    @tracker = {}
    File.open(@options[:tracker]) { |file| @tracker = YAML.load(file) } if @options[:tracker] && File.file?(@options[:tracker])
    FolderScanner.new.run(ARGV, @options[:scanner]) do |full_path, relative_path, name, should_include, is_file|
      next unless is_file && should_include
        entry = file_to_wiki_info(full_path, relative_path)
        server_name = entry[:server_name]
        if files[server_name]
          puts "Warning: Same server page ID for #{entry} and #{files[server_name]}"
        else
          files[server_name] = entry
        end
    end
    unless @tracker.empty?
      server_revisions = cx.page_rev_ids(files.keys)
      would_overwrite = false
      files.each_pair do |title, entry|
        if server_revisions[title] && @tracker[title] && @tracker[title][:prev]
          if server_revisions[title] > @tracker[title][:prev]
            puts "Warning: Would overwrite externally edited page #{title}"
            would_overwrite = true
          end
        end
      end
      exit 1 if would_overwrite && !@options[:force]
    end
    begin
      files.sort.each do |name, val|
        process_file(val)
      end
    ensure
      File.open(@options[:tracker], "w") { |file| YAML.dump(@tracker, file) } if @options[:tracker]
    end
  end
end
App.new.run

