class MediaWikiTable
  alias_method :__instance_exec, :instance_exec
  instance_methods.each { |meth| undef_method(meth) unless meth =~ /\A__/ }
  def method_missing(meth, *args, &block)
    @delegate.send(meth, *args, &block)
  end
  def initialize deleg, options = {}, &block
    @delegate = deleg
    @cols = options[:cols] || []
    @col_ids = @cols.map { |e| e.is_a?(Hash) ? e[:id] : e }
    @options = options # border="1" cellpadding="20" cellspacing="0"
    @output = "{|#{hash_to_styles(@options[:style])}\n"
    @buffered_rows = @options[:auto_rowspan] ? [] : nil
    if options[:caption]
      style = options[:caption_style] || {}
      style[:align] = "bottom" unless style[:align]
      add_cell "|+", nil, options[:caption], style
    end
    __instance_exec(&block)
  end
  def column id = nil, options = {}
    unless id
      id = options[:id]
      raise "Need a column ID" if id.nil?
    end
    if options.empty?
      @cols << {}
    else
      @cols << options
    end
    @col_count = @cols.size
    @col_ids << id
  end
  def add_cell header, col, content = "", style = {}
    unless col.nil?
      style = style.merge(@cols[col][:style] || {})
    end
    header = "!" if style.delete(:header)
    style = hash_to_styles(style)
    self << "#{header || "|"}#{style != "" ? style + " |" : ""} #{content}\n"
  end
  def write_row buffer
    self << "|-\n"
    buffer.each { |c| add_cell(*c) if c }
  end
  def handle_row_spans new_row
    latest_row = @buffered_rows.last
    new_index = @buffered_rows.size
    @buffered_rows << new_row
    if !latest_row
      @running_spans = @col_count.times.map { 0 }
      return
    end
    all_blank = true
    @col_count.times do |c|
      running_since = @running_spans[c]
      first_row = @buffered_rows[running_since]
      if first_row[c] != new_row[c]
        all_blank = false
        @running_spans[c] = new_index
        unless new_index == running_since + 1
          span = {:rowspan => (new_index - running_since).to_s}
          if first_row[c].length == 3
            first_row[c] << span
          else
            first_row[c][3].merge!(span)
          end
        end
      else
        new_row[c] = nil
      end
    end
    @buffered_rows.pop if all_blank
  end
  def flush_table
    last_index = @buffered_rows.size - 1
    @col_count.times do |c|
      running_since = @running_spans[c]
      if running_since < last_index
        row = @buffered_rows[running_since]
        span = {:rowspan => (last_index - running_since + 1).to_s}
        if row.length == 3
          row[c] << span
        else
          row[c][3].merge!(span)
        end
      end
    end
    @buffered_rows.each { |r| write_row r }
  end
  def add_row cells, header
    args = Array(@col_count.times.map do |i|
      cells[i] ? [header, i] + Array(cells[i]) : nil
    end)
    if @buffered_rows
      handle_row_spans args
    else
      write_row args
    end
  end
  def get_cells data
    styles = data[:style_for] || {}
    @col_ids.map do |id|
      value = data[id]
      value = [value, styles[id] || {}]
      value
    end
  end
  def header_row data
    data = get_cells data unless data.is_a?(Array)
    add_row data, "!"
  end
  def row data
    data = get_cells data unless data.is_a?(Array)
    add_row data, "|"
  end
  def columnify col_count, enum
    @cols = [{}] * col_count
    @col_count = col_count
    @col_ids = Array(col_count.times)
    enum = Array(enum)
    item_count = enum.count
    row_count = item_count / col_count
    rest = item_count % col_count
    row_count += 1 if rest > 0
    row_count.times do |r|
      row Array(col_count.times.map { |i| enum[r * col_count + i] || "" })
    end
  end
  def hash_to_styles hash = {}
    result = []
    return "" if !hash || hash.empty?
    hash.each_pair { |name, val| result << " #{name}=\"#{val}\"" }
    result.join("")
  end
  def << data
    if data.is_a?(String)
      @output << data
    else
      row data
    end
  end
  def to_s
    flush_table if @buffered_rows
    @output + "|}"
  end
end

# Helpers for writing media wiki formatted documents
module MediaWikiHelpers
=begin rdoc
  <%= make_table(:caption => "A table", :auto_rowspan => true) do
    column :a
    column :b
    column :c
    header_row ["A", "Bee", "Cee"]
    row :a=> "a", :b => ["b", {:rowspan => 2, :header => true}], :c => "c"
    row [1, nil, 2]
    row :a=> "a", :b => "b", :c => "c", :styles_for => {:b => {:header => true}}
    row Array(3.times)
  end %>
=end
  def make_table options = {}, &blk
    options[:style] = {:class => "wikitable"} unless options[:style]
    (MediaWikiTable.new self, options, &blk).to_s
  end
  # wraps in <nowiki> tags
  def nowiki text, &block
    wrap_tag(text, "nowiki", &block)
  end
  # Creates a [[File: path]] link
  def image path
    wrap(path, "[[File:", "]]")
  end
  # Creates a link to the provided internal url, with an optional title
  def internal_link url, title = nil
    wrap("#{url}#{title ? "|#{title}" : ""}", "[[", "]]")
  end
  # Include specified URL http://www.mediawiki.org/wiki/Templates
  def include_template url
    "{{:#{url}}}"
  end
  # Builds a parser function call
  # 
  # Reference: http://www.mediawiki.org/wiki/Help:Extension:ParserFunctions
  def func_call name, *args
    args = args.map { |e| e.to_s }
    args.pop while args.last == ""
    "{{##{name}#{wrap(args.join(" | "), ": ", "")}}}"
  end
  def if_exists url, if_true, if_false = nil
    func_call "ifexist", url, if_true, if_false
  end
  # Includes the template #{url}_Manual if it exists, falling
  # back to url, or empty
  def overiddable_template url
    override_name = "#{url}_Manual"
    if_exists override_name, include_template(override_name), if_exists(url, include_template(url))
  end
  # Builds an internal link to the provided QS::QSObject
  def qs_object_link obj, type = nil
    internal_link url_for(obj, type), obj.name
  end
  # Builds an internal link to the specified QS::ObjectType
  # [type] QS::ObjectType to link to
  # [file_types] Optional. An array of file types displayed if QS::ObjectType#files? of type is true
  def qs_object_type_link type, file_types = nil
    name = type.name
    internal_link(url_for(type, nil), name) + (file_types && type.files? ?
      hover(" (types)", wrap(enum_with_sep(file_types, ' or '), ' (', ')')) || "" : "")
  end
  # Replaces html <a href="http:.."> formatted links in str into
  # wiki media [http:...] links
  def html_links_to_wikimedia str
    return str unless str.is_a?(String)
    str.gsub(/<\s*a\b([^>]+)>/i) do |match|
      attrs = {}
      $1.scan(/([^ =]+)=(?:'([^']+)'|"([^"]+)"|([^ >]+))/i) do |matches|
        attrs[$1] = matches.drop(2).select {|e| e}.first
      end
      raise "Failed to understand html #{str.inspect}" unless attrs['href']
      "[#{attrs['href']} "
    end.gsub(/<\/a>/i, "]")
  end
  def external_link url, title = nil
    wrap("#{url}#{title ? " #{title}" : ""}", "[", "]")
  end
  # Generates a span with specified title
  def hover label, text
    wrap(text, "<span title=\"", "\" style=\"border-bottom:1px dotted\">#{label}</span>")
    #wrap(text, "{{H:title|#{label}|", "}}")
  end
  def youtube id
    wrap(id, "{{#ev:youtube|", "}}")
  end
  def redirect target_link
    "#REDIRECT #{target_link}"
  end
  def list(enum, depth = 1)
    prefix = "\n#{"*" * depth} "
    wrap(enum ? enum.join(prefix) : nil, prefix, "")
  end
end
