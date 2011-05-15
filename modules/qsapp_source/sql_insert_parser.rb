require "strscan"
# Flimsy-as-hell SQL insert statement parser
class SQLInsertParser < StringScanner
  def skip_ws
    scan(/\s+/) || scan(/--.*\n/) || scan(/\/\*.*\*\//)
  end
  def get_string delim
    rx = "(#{delim}#{delim}|[^#{delim}]*)*#{delim}"
    res = scan(Regexp.new(rx))
    res = res[0..-2] if res
    res
  end
  def get_token
    return nil if eos?
    skip_ws
    return nil if eos?
    {
      :ident => /[a-z_][a-z_0-9]*/i,
      :int => /\d+/,
      :str_start => /[`"']/,
      :lpar => /\(/,
      :rpar => /\)/,
      :op => /[,=]/,
      :stend => /;/
    }.each_pair do |token, rx|
      match = scan(rx)
      next unless match
      if token == :str_start
        return [:str, get_string(match).gsub(match * 2, match)]
      elsif token == :lpar
        group = []
        item = get_token
        while item && item[0] != :rpar
          group << item
          item = get_token
        end
        return [:group, group]
      end
      return [token, match]
    end
    nil
  end
  def get_statement
    statement = []
    token = get_token
    while token && token[0] != :stend
      statement << token
      token = get_token
    end
    return nil if statement.empty? && eos?
    return statement
  end
  def self.parse_group group
    raise "Not a group : #{group.inspect}" unless group[0] == :group && group[1].is_a?(Array)
    items = group[1]
    result = []
    items.count.times do |i|
      pair = items[i]
      if i % 2 == 1
        raise "Expected ',' but got #{pair.inspect}" unless pair == [:op, ","]
      else
        result << case pair[0]
        when :str
          pair[1]
        when :int
          pair[1].to_i
        when :group
          parse_group([:group, pair[1]])
        else
          raise "Unexpected #{pair.inspect}"
        end
      end
    end
    result
  end
  def self.parse_insert_statement statement
    table_name = statement[2][1]
    columns = parse_group(statement[3])
    rows = parse_group([:group, statement.drop(5)]).map do |row|
      res = {}
      row.each_index { |i| res[columns[i]] = row[i] }
      res
    end
    actual_columns = []
    columns.each do |c|
      actual_columns << c if rows.any? { |r| r[c] && r[c]  != "" }
    end
    { :columns => columns, :table_name => table_name, :rows => rows, :actual_columns => actual_columns,  }
  end
  def self.parse data
    tables = []
    scanner = self.new(data)
    while stat = scanner.get_statement
      tables << parse_insert_statement(stat) if stat[0] == [:ident, "INSERT"]
    end
    tables
  end
end

