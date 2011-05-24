require 'pathname'
require 'media_wiki'
require "sql_insert_parser"
require "yaml"

class BunchOTables
  def self.remove_empty_keys hash, *keys
    keys.map { |k| [k, k.to_sym] }.flatten.each do |f|
      val = hash[f]
      unless val.nil?
        hash.delete(f) if val.to_s == "" || val.to_s == "0"
      end
    end
  end
  def initialize *files, &reader
    @tables ||= []
    files.each do |f|
      tables = yield f
      @tables += SQLInsertParser.parse(tables) if tables
    end
  end
  def find_table(name, &block)
    enum_for(:find_table, name) unless block_given?
    name = name.to_s.downcase
    @tables.select { |e| e[:table_name].downcase == name }.each(&block)
  end
  def empty?
    @tables.empty?
  end
  def index(table_name, key_field, *fields)
    table = Array(find_table(table_name))
    raise "Searching table #{table_name}: #{table.count} results" if table.count != 1
    table = table.first[:rows]
    res = {}
    table.each do |row|
      val = if fields.length == 1
        row[fields.first]
      else
        val = {}
        fields.each { |f| val[f] = row[f] }
        val
      end
      key = row[key_field]
      prev = res[key]
      if prev.is_a?(Array)
        prev << val
      elsif res[key]
        res[key] = [prev, val]
      else
        res[key] = val
      end
    end
    if fields.length > 1
      res.each_pair do |key, row|
        Array(row.keys).each do |k|
          row.delete(k) if row[k] == ""
        end
      end
    end
    res
  end
  def self.merge_into_hash_of_common_keys divergence_key, list
    columns = list.map(&:keys).flatten.uniq
    first_value_per_col = {}
    columns.each { |c| first_value_per_col[c] = list.select { |r| r[c] }.first[c] rescue nil }
    common_columns = columns.select { |c| list.all? { |r| r[c].nil? || r[c] == first_value_per_col[c] } }
    res = list.first.dup
    (res.keys - common_columns).each { |k| res.delete(k) }
    res[divergence_key] = []
    list.each do |hash|
      hash = hash.dup
      common_columns.each { |c| hash.delete(c) }
      res[divergence_key] << hash
    end
    res
  end
  def merge_into_plugins
    plugins_by_id = {}
    find_table(:plugins).map { |e| e[:rows] }.flatten.each do |row|
      pid = (row["id"] || row["bundle_id"])
      # There's a case issue for just this one, so id rather this than loosing case for all
      pid = "com.blacktree.Quicksilver.TKDesktopPlugin" if pid == "com.blacktree.quicksilver.TKDesktopPlugin"
      (plugins_by_id[pid] ||= []) << row
    end
    categories = index(:categories, *%w[category_id category_name])
    applications = index(:applications, *%w[bundle_id name])
    authors = index(:authors, *%w[author_id author_name author_url author_description])
    cats_per_plug = index(:related_categories, *%w[plugin_id category_id])
    cats_per_plug.keys.each { |k| cats_per_plug[k] = Array(cats_per_plug[k]).map { |c| categories[c] }.select {|e|e.to_s.length > 0} }
    app_per_plug = index(:related_bundles, *%w[plugin_bundle_id app_bundle_id])
    app_per_plug.keys.each { |k| app_per_plug[k] = Array(app_per_plug[k]).select {|e|e.to_s.length > 0} }
    result = {}
    plugins_by_id.each_pair do |name, val|
      res = BunchOTables.merge_into_hash_of_common_keys(:versions, val)
      res[:categories] = Array(cats_per_plug[name])
      res[:related] = Array(app_per_plug[name])
      author_id = res.delete("author_id")
      res[:author] = authors[author_id] || { }
      res[:author][:id] = author_id if author_id
      unless res[:related]
        raise "Case error" if app_per_plug.keys.any? { |k| k.downcase == name.downcase }
      end
      BunchOTables.remove_empty_keys res, *%w[categories related feature url version hidden secret current author]
      if res[:versions].empty? || res[:versions] == [{}]
        res.delete(:versions)
      else
        res[:versions].each do |v|
          BunchOTables.remove_empty_keys v, *%w[version downloads build modified secret]
        end
      end
      result[name] = res
    end
    result
  end
end

App.register do
  App.extension_point :load_data_file
  def load_data_file filename
    File.read(Pathname.new($0).dirname + "data/#{filename}")
  rescue Errno::ENOENT => e
    @logger.warn "File data/#{filename} not found"
    nil
  end
  def template_data
    { :qsapp => @qsapp }
  end
  def find_tags tagname, input
    result = []
    input.scan(/<\s*#{tagname}\b([^>]+?)(?:>(.*?)<\/\s*#{tagname}\s*>|\/>)/i) do |attributes|
      attrs = {}
      content = $2
      $1.scan(/([^ =]+)=(?:'([^']+)'|"([^"]+)"|([^ >]+))/i) do |matches|
        attrs[$1] = matches.drop(2).select {|e| e}.first
      end
      result << [attrs, content ? content.strip() : content]
    end
    result
  end
  def parse_qsapp_plugin_table wikitable_name_to_id
    plugin_table = load_data_file("qsapp_com_plugins.html")
    return nil unless plugin_table
    result = {}
    find_tags("div", plugin_table).
      select { |attrs, content| attrs['class'] && attrs['class'].start_with?("box") && !attrs['class']["head"] }.
      each_slice(3).
      map do |name, version, updated|
        links = find_tags("a", name[1])
        icons = find_tags("img", name[1])
        icon = (icons.first || [{}]).first['src']
        entry = {
          'name' => links.first[1],
          'download' => links.first[0]['href']
        }
        entry['icon'] = "http://qsapp.com/plugins/#{icon}" if icon && icon != "images/noicon.png"
        entry['updated'] = updated[1] if updated[1].to_s.strip() != "" && updated[1].to_s.strip() != "0000-00-00"
        entry['version'] = version[1] if version[1].to_s.strip() != ""
        entry
      end.
      each { |entry| result[entry['name']] = entry }
    compat_by_id = {}
    id_unknown = {}
    result.each_pair do |name, entry|
      id = wikitable_name_to_id[name]
      unless id
        id = @qsapp.map {|pluginid, tables| [pluginid, (tables[:legacy] || {})['name']] }.select { |e| e[1] == name }.first
        id = id.nil? ? nil : id.first
      end
      if id
        compat_by_id[id] = entry
      else
        id_unknown[name] = entry
      end
    end
    @logger.warn("Plugins have information in QSApps.com/plugins, but couldn't find their id in data/wikitable_name_to_id.yaml:", *id_unknown.keys) unless id_unknown.empty?
    compat_by_id
  end
  def parse_wiki_compat_table plugin_ref
    rows = plugin_ref.split(/\n\|-/).drop(1).map { |e| e.split(/\n\s*[|!]\s*/).drop(1) }
    rows.pop ; rows.shift
    res = {}
    rows.each do |e|
      raise "dup: #{e.inspect}" if res[e[0]]
      row = {
        :qs_compat => e[1],
        :os_compat => e[2],
        :current => e[3],
      }
      row[:description] = e[4] if e[4]
      row[:tutorial] = e[5] if e[5]
      if row[:tutorial] =~ /\[\[([^\[\]|]+)(?:\|\s*([^\]]+))?\]\]/
        name = $1
        title = $2 || $1
        filename = name.gsub(" ", "_") + ".txt"
        row['Tutorials'] = [{'title' => title, 'wikilink' => name}]
        data = load_data_file(filename)
        row[:wiki_page] = data if data
      end
      res[e[0].gsub(" (+)", "")] = row
    end
    res
  end
  def read_wiki_compatibility_table(wikitable_name_to_id)
    compat_table = load_data_file("plugin_reference.txt")
    return nil unless compat_table
    compat_table = parse_wiki_compat_table(compat_table)
    compat_by_id = {}
    id_unknown = {}
    compat_table.each_pair do |name, val|
      id = wikitable_name_to_id[name]
      unless id
        id = @qsapp.map {|pluginid, tables| [pluginid, (tables[:legacy] || {})['name']] }.select { |e| e[1] == name }.first
        id = id.nil? ? nil : id.first
      end
      if id
        compat_by_id[id] = val
      else
        id_unknown[name] = val
      end
    end
    @logger.warn("Plugins have information in QSApps.com Plugin reference wiki, but couldn't find their id in data/wikitable_name_to_id.yaml:", *id_unknown.keys) unless id_unknown.empty?
    compat_by_id
  end
  def read_plugin_repository_locations
    pairs = {}
    data = load_data_file("repo_locations.txt")
    return nil unless data
    data.strip.split(/\r\n?|\n/).map { |e| e.split("\t") }.each do |k, r|
      k = k && k.strip
      r = r && r.strip
      if k && r && k.length > 0 && r.length > 0
        pairs[k] = r
      end
    end
    unknowns = pairs.keys - @qsapp.keys
    @logger.debug("Plugins have repositories in data/repo_locations.txt, but no wiki information", *unknowns) unless unknowns.empty?
    pairs
  end
  def startup *args
    @logger = App.require_one :logger
    @qsapp = {}

    wikitable_name_to_id = load_data_file("wikitable_name_to_id.yaml")
    wikitable_name_to_id = wikitable_name_to_id ? YAML.load(wikitable_name_to_id) : {}

    blacktree = BunchOTables.new(*%w[blacktr_qsplugin.sql blacktr_qsplugin2.sql]) { |f| load_data_file(f) }
    unless blacktree.empty?
      blacktree = blacktree.merge_into_plugins
      blacktree.each_pair { |name, val| (@qsapp[name] ||= {})[:legacy] = val }
    end
    if wiki = read_wiki_compatibility_table(wikitable_name_to_id)
      wiki.each_pair { |name, val| (@qsapp[name] ||= {})[:wiki] = val }
    end
    if repos = read_plugin_repository_locations
      repos.each_pair { |name, val| (@qsapp[name] ||= {})[:repository] = val }
    end
    if plugin_table = parse_qsapp_plugin_table(wikitable_name_to_id)
      plugin_table.each_pair { |name, val| (@qsapp[name] ||= {})[:info] = val }
    end
  end
end