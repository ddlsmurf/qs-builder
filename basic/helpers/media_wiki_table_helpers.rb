module MediaWikiTableHelpers
=begin rdoc
  Yields in the context of Table.
  Upon completion of the block, returns the table in wikimedia format.

  options can have:
  - :style : A style Hash to apply to the whole table entry
  - :caption : A content to use as the table's caption
  - :caption_style : A style hash for ... you guessed it .. the caption
  - :auto_rowspan : Sets the table into a mode where adding rows with the 
    same content as the cell above them makes them increase the rowspan of
    the cell above

    <%= 
    make_table(:caption => "A table", :auto_rowspan => true) do
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
  def make_table options = {}, &blk # :yields: 
    options[:style] = {:class => "wikitable"} unless options[:style]
    (Table.new self, options, &blk).to_s
  end
  
  class Table
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
    # Define a column id to use to find data when passing a Hash to #row.
    # [options] Can contain a :style Hash added to all cells of this column
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
      @output << "#{header || "|"}#{style != "" ? style + " |" : ""} #{content}\n"
    end
    protected :add_cell
    def write_row buffer
      @output << "|-\n"
      buffer.each { |c| add_cell(*c) if c }
    end
    protected :write_row
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
    protected :handle_row_spans
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
    protected :flush_table
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
    protected :add_row
    def get_cells data
      styles = data[:style_for] || {}
      @col_ids.map do |id|
        value = data[id]
        value = [value, styles[id] || {}]
        value
      end
    end
    protected :get_cells
    # Same as #row but with header cells
    def header_row data
      data = get_cells data unless data.is_a?(Array)
      add_row data, "!"
    end
    # Add a row of data to the output. Data should be an array with the right number
    # of cells, or a Hash of {col_id => col_value, :styles_for => {col_id => {...}}}
    def row data
      data = get_cells data unless data.is_a?(Array)
      add_row data, "|"
    end
    # Present enum in col_count columns
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
    protected :hash_to_styles
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
  
end